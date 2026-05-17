"""
SBERT-based multi-label activity classifier.

Purpose:
- Encodes normalized messages
- Trains One-vs-Rest activity classifier
- Produces probabilistic activity predictions

This module is intentionally isolated so that:
- embeddings are deterministic
- classifiers are reusable
- training and inference are explicit
"""

from sentence_transformers import SentenceTransformer
from sklearn.preprocessing import MultiLabelBinarizer
from sklearn.multiclass import OneVsRestClassifier
from sklearn.linear_model import LogisticRegression


class SBERTActivityClassifier:
    def __init__(
        self,
        model_name="all-MiniLM-L6-v2",
        max_iter=2000,
        threshold=0.3,
    ):
        self.model_name = model_name
        self.threshold = threshold

        self.encoder = SentenceTransformer(model_name)
        self.mlb = MultiLabelBinarizer()
        self.clf = OneVsRestClassifier(
            LogisticRegression(max_iter=max_iter)
        )

    def fit(self, texts, label_sets):
        """
        texts: list[str]
        label_sets: list[set[str]]
        """
        X = self.encoder.encode(texts, show_progress_bar=True)
        Y = self.mlb.fit_transform(label_sets)

        self.clf.fit(X, Y)
        return self

    def predict_proba(self, texts):
        """
        Returns list[dict[label -> probability]]
        """
        X = self.encoder.encode(texts, show_progress_bar=False)
        probs = self.clf.predict_proba(X)

        results = []
        for row in probs:
            row_dict = {
                label: p
                for label, p in zip(self.mlb.classes_, row)
                if p >= self.threshold
            }
            results.append(row_dict)

        return results
