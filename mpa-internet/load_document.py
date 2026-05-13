"""Script to manually load MPA_DOCUMENT.md into Qdrant with 4096-dim embeddings."""

import json
import uuid
import httpx

EMBEDDING_URL = "http://10.10.8.154:1234/v1/embeddings"
EMBEDDING_MODEL = "text-embedding-qwen3-embedding-8b-fixed"
API_KEY = "lm-studio"
QDRANT_URL = "http://localhost:6333"
COLLECTION = "sam-documents"
DOCUMENT_PATH = "./documents/MPA_DOCUMENT.md"

CHUNK_SIZE = 2048
CHUNK_OVERLAP = 400


def read_document(path):
    with open(path, "r") as f:
        return f.read()


def split_by_sections(text):
    """Split markdown by ## headers into meaningful chunks."""
    lines = text.split("\n")
    chunks = []
    current_chunk = []
    current_header = ""

    for line in lines:
        if line.startswith("## ") and current_chunk:
            chunk_text = "\n".join(current_chunk).strip()
            if chunk_text:
                chunks.append({"text": chunk_text, "header": current_header})
            current_chunk = [line]
            current_header = line.strip("# ").strip()
        else:
            current_chunk.append(line)
            if not current_header and line.startswith("# "):
                current_header = line.strip("# ").strip()

    # Last chunk
    if current_chunk:
        chunk_text = "\n".join(current_chunk).strip()
        if chunk_text:
            chunks.append({"text": chunk_text, "header": current_header})

    # Further split chunks that are too large
    final_chunks = []
    for chunk in chunks:
        text = chunk["text"]
        if len(text) > CHUNK_SIZE:
            # Split large chunks with overlap
            start = 0
            while start < len(text):
                end = start + CHUNK_SIZE
                sub_text = text[start:end]
                final_chunks.append({
                    "text": sub_text.strip(),
                    "header": chunk["header"],
                })
                start = end - CHUNK_OVERLAP
        else:
            final_chunks.append(chunk)

    return final_chunks


def get_embeddings(texts):
    """Get embeddings from LM Studio."""
    client = httpx.Client(timeout=120.0)
    response = client.post(
        EMBEDDING_URL,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {API_KEY}"},
        json={"input": texts, "model": EMBEDDING_MODEL},
    )
    response.raise_for_status()
    data = response.json()
    return [item["embedding"] for item in data["data"]]


def upload_to_qdrant(points):
    """Upload points to Qdrant."""
    client = httpx.Client(timeout=60.0)
    response = client.put(
        f"{QDRANT_URL}/collections/{COLLECTION}/points",
        headers={"Content-Type": "application/json"},
        json={"points": points},
    )
    response.raise_for_status()
    return response.json()


def main():
    print(f"Reading document: {DOCUMENT_PATH}")
    text = read_document(DOCUMENT_PATH)
    print(f"Document size: {len(text)} characters")

    print("Splitting into chunks...")
    chunks = split_by_sections(text)
    print(f"Created {len(chunks)} chunks")

    for i, chunk in enumerate(chunks):
        print(f"  Chunk {i}: [{chunk['header']}] {len(chunk['text'])} chars")

    print("\nGenerating embeddings (this may take a moment)...")
    texts = [c["text"] for c in chunks]

    # Batch embeddings
    batch_size = 8
    all_embeddings = []
    for i in range(0, len(texts), batch_size):
        batch = texts[i : i + batch_size]
        print(f"  Embedding batch {i // batch_size + 1}/{(len(texts) + batch_size - 1) // batch_size}...")
        embeddings = get_embeddings(batch)
        all_embeddings.extend(embeddings)

    print(f"Generated {len(all_embeddings)} embeddings (dim={len(all_embeddings[0])})")

    print("\nUploading to Qdrant...")
    points = []
    for i, (chunk, embedding) in enumerate(zip(chunks, all_embeddings)):
        point_id = str(uuid.uuid4())
        points.append({
            "id": point_id,
            "vector": embedding,
            "payload": {
                "text": chunk["text"],
                "source": "MPA_DOCUMENT.md",
                "header": chunk["header"],
                "chunk_index": i,
                "document_type": "MPA_DOCUMENT",
            },
        })

    result = upload_to_qdrant(points)
    print(f"Upload result: {result}")
    print(f"\nSuccessfully loaded {len(points)} chunks into Qdrant collection '{COLLECTION}'")


if __name__ == "__main__":
    main()
