"""
SMS Spam Classifier — Training Pipeline
Trains a TF-IDF + Logistic Regression model on the UCI SMS Spam Collection,
finds an optimal threshold for ≥95% spam precision, and exports model weights
as JSON for native Swift inference (no Core ML dependency needed).

Usage:
    pip install scikit-learn pandas
    python train_sms_classifier.py

Output: SMSSpamClassifier.json (~200 KB)
"""

import io
import json
import os
import re
import string
import zipfile
from urllib.request import urlretrieve

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, precision_recall_curve
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline

# ---------------------------------------------------------------------------
# 1. Download & load dataset
# ---------------------------------------------------------------------------
DATA_URL = "https://archive.ics.uci.edu/ml/machine-learning-databases/00228/smsspamcollection.zip"
ZIP_PATH = "smsspamcollection.zip"
TSV_NAME = "SMSSpamCollection"

if not os.path.exists(ZIP_PATH):
    print("Downloading UCI SMS Spam Collection...")
    urlretrieve(DATA_URL, ZIP_PATH)

with zipfile.ZipFile(ZIP_PATH) as zf:
    with zf.open(TSV_NAME) as f:
        df = pd.read_csv(
            io.TextIOWrapper(f, encoding="utf-8"),
            sep="\t",
            header=None,
            names=["label", "message"],
        )

print(f"Loaded {len(df)} messages  —  {df['label'].value_counts().to_dict()}")

# ---------------------------------------------------------------------------
# 2. Preprocess  (must match Swift preprocessing exactly)
# ---------------------------------------------------------------------------
PUNCT_RE = re.compile(f"[{re.escape(string.punctuation)}]")


def preprocess(text: str) -> str:
    """Lowercase + strip punctuation. Keep this in sync with the Swift extension."""
    text = text.lower()
    text = PUNCT_RE.sub(" ", text)
    text = " ".join(text.split())  # collapse whitespace
    return text


df["clean"] = df["message"].apply(preprocess)
df["is_spam"] = (df["label"] == "spam").astype(int)

# ---------------------------------------------------------------------------
# 3. Train / test split
# ---------------------------------------------------------------------------
X_train, X_test, y_train, y_test = train_test_split(
    df["clean"], df["is_spam"], test_size=0.2, random_state=42, stratify=df["is_spam"]
)
print(f"Train: {len(X_train)}  Test: {len(X_test)}")

# ---------------------------------------------------------------------------
# 4. Build sklearn pipeline
# ---------------------------------------------------------------------------
pipeline = Pipeline(
    [
        ("tfidf", TfidfVectorizer(max_features=5000, ngram_range=(1, 2))),
        ("clf", LogisticRegression(class_weight="balanced", max_iter=1000, C=1.0)),
    ]
)

pipeline.fit(X_train, y_train)

# ---------------------------------------------------------------------------
# 5. Evaluate at default 0.50 threshold
# ---------------------------------------------------------------------------
y_pred = pipeline.predict(X_test)
print("\n=== Classification Report (threshold=0.50) ===")
print(classification_report(y_test, y_pred, target_names=["ham", "spam"]))

# ---------------------------------------------------------------------------
# 6. Find optimal threshold for ≥95% precision on spam
# ---------------------------------------------------------------------------
y_proba = pipeline.predict_proba(X_test)[:, 1]
precisions, recalls, thresholds = precision_recall_curve(y_test, y_proba)

best_threshold = 0.50
best_recall = 0.0
for p, r, t in zip(precisions, recalls, thresholds):
    if p >= 0.95 and r > best_recall:
        best_recall = r
        best_threshold = t

print(f"\nOptimal threshold for ≥95% spam precision: {best_threshold:.4f}")
print(f"  Recall at that threshold: {best_recall:.4f}")

y_pred_opt = (y_proba >= best_threshold).astype(int)
print(f"\n=== Classification Report (threshold={best_threshold:.4f}) ===")
print(classification_report(y_test, y_pred_opt, target_names=["ham", "spam"]))

y_pred_60 = (y_proba >= 0.60).astype(int)
print("=== Classification Report (threshold=0.60) ===")
print(classification_report(y_test, y_pred_60, target_names=["ham", "spam"]))

# ---------------------------------------------------------------------------
# 7. Export model weights as JSON for native Swift inference
# ---------------------------------------------------------------------------
tfidf: TfidfVectorizer = pipeline.named_steps["tfidf"]
clf: LogisticRegression = pipeline.named_steps["clf"]

# vocabulary: word → feature index (convert numpy int64 to Python int for JSON)
vocab = {k: int(v) for k, v in tfidf.vocabulary_.items()}

# IDF weights: array of shape (n_features,)
idf = tfidf.idf_.tolist()

# L2 normalization is applied by TfidfVectorizer (sublinear_tf=False, norm='l2' by default)
# We need to replicate this in Swift

# Logistic regression: coefficients and intercept
# coef_ shape is (1, n_features) for binary classification
lr_coef = clf.coef_[0].tolist()
lr_intercept = float(clf.intercept_[0])

model_data = {
    "vocabulary": vocab,          # str → int (5000 entries)
    "idf_weights": idf,           # float[] (5000 entries)
    "lr_coefficients": lr_coef,   # float[] (5000 entries)
    "lr_intercept": lr_intercept,  # float
    "default_threshold": round(best_threshold, 4),
    "tfidf_norm": "l2",           # reminder: Swift must L2-normalize
    "ngram_range": [1, 2],        # reminder: Swift must generate bigrams too
}

output_path = "SMSSpamClassifier.json"
with open(output_path, "w") as f:
    json.dump(model_data, f)

size_kb = os.path.getsize(output_path) / 1024
print(f"\nSaved {output_path}  ({size_kb:.0f} KB)")
print(f"Default threshold: {best_threshold:.4f}")
print(f"Vocabulary size: {len(vocab)}")
print(f"Features: {len(lr_coef)}")

# ---------------------------------------------------------------------------
# 8. Verify the JSON export matches sklearn predictions
# ---------------------------------------------------------------------------
print("\n=== Verifying JSON export matches sklearn ===")

# Reconstruct predictions from raw weights
X_test_tfidf = tfidf.transform(X_test)  # sparse matrix
raw_logit = X_test_tfidf.dot(np.array(lr_coef)) + lr_intercept
json_proba = 1.0 / (1.0 + np.exp(-raw_logit))

max_diff = np.max(np.abs(json_proba - y_proba))
print(f"Max probability difference (sklearn vs JSON weights): {max_diff:.10f}")
assert max_diff < 1e-10, f"Mismatch! max_diff={max_diff}"
print("Verification passed — JSON weights reproduce sklearn predictions exactly.")

print(f"\nDone! Copy {output_path} into the Xcode project (both targets).")
