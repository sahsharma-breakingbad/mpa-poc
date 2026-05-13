"""Custom tools for Qdrant vector DB synchronization.

Provides delete-by-document-type and file write capabilities
for the VectorDBSyncAgent to properly replace old high-risk port
entries in the vector database.
"""

import os
import re
import uuid
import logging
import tempfile
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# Default configuration - overridden by environment variables
QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
QDRANT_API_KEY = os.environ.get("QDRANT_API_KEY", "")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "sam-documents")
QDRANT_EMBEDDING_DIMENSION = int(os.environ.get("QDRANT_EMBEDDING_DIMENSION", "1536"))
DOCUMENTS_PATH = os.environ.get("DOCUMENTS_PATH", "./documents")

# Embedding API configuration
OPENAI_EMBEDDING_MODEL = os.environ.get("OPENAI_EMBEDDING_MODEL", "text-embedding-ada-002")
OPENAI_EMBEDDING_API_KEY = os.environ.get("OPENAI_EMBEDDING_API_KEY", "")
OPENAI_EMBEDDING_API_ENDPOINT = os.environ.get("OPENAI_EMBEDDING_API_ENDPOINT", "https://api.openai.com/v1")


def delete_qdrant_documents_by_type(document_type: str) -> dict:
    """Delete all existing Qdrant entries for a given document type.

    Uses the 'file_name' payload field (which is what the RAG pipeline stores)
    to filter and delete entries. The document_type arg is treated as the
    file_name (e.g., "high-risk-ports_v1" matches "high-risk-ports_v1.md").

    Args:
        document_type: The document type identifier. Will match against both
                       'file_name' (e.g., "high-risk-ports_v1.md") and
                       'document_type' payload fields for compatibility.

    Returns:
        dict with status, document_type deleted, and any errors.
    """
    try:
        import httpx
    except ImportError:
        return {
            "status": "error",
            "document_type": document_type,
            "error": "httpx library not available. Install with: pip install httpx",
        }

    headers = {"Content-Type": "application/json"}
    if QDRANT_API_KEY:
        headers["api-key"] = QDRANT_API_KEY

    # Build file_name variants to match against
    file_name = document_type if document_type.endswith(".md") else f"{document_type}.md"

    try:
        client = httpx.Client(timeout=60.0)
        # Delete by file_name (RAG pipeline field) using "should" (OR) logic
        # to match entries from both RAG pipeline and reingest
        response = client.post(
            f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete",
            headers=headers,
            json={
                "filter": {
                    "should": [
                        {"key": "file_name", "match": {"value": file_name}},
                        {"key": "document_type", "match": {"value": document_type}},
                    ]
                }
            },
        )
        response.raise_for_status()
        result = response.json()
        logger.info(f"Deleted Qdrant entries for file_name='{file_name}' / document_type='{document_type}': {result}")
        return {
            "status": "success",
            "document_type": document_type,
            "file_name": file_name,
            "qdrant_response": result,
            "message": f"Successfully deleted all entries with file_name='{file_name}' or document_type='{document_type}' from collection '{QDRANT_COLLECTION}'",
        }
    except Exception as e:
        logger.error(f"Failed to delete Qdrant entries for '{document_type}': {e}")
        return {
            "status": "error",
            "document_type": document_type,
            "error": str(e),
        }


def write_document_to_file(content: str, filename: str) -> dict:
    """Write document content to a file in the documents directory.

    This overwrites the existing file, enabling the workflow to update
    the original high-risk-ports_v1.md (or any document) with new content.

    Args:
        content: The markdown content to write.
        filename: The filename to write to (e.g., "high-risk-ports_v1.md").
                  Written to the DOCUMENTS_PATH directory.

    Returns:
        dict with status, file_path written, and file size.
    """
    file_path = os.path.join(DOCUMENTS_PATH, filename)

    try:
        os.makedirs(os.path.dirname(file_path), exist_ok=True)

        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)

        file_size = os.path.getsize(file_path)
        logger.info(f"Wrote document to {file_path} ({file_size} bytes)")
        return {
            "status": "success",
            "file_path": file_path,
            "filename": filename,
            "file_size": file_size,
            "message": f"Successfully wrote {file_size} bytes to {file_path}",
        }
    except Exception as e:
        logger.error(f"Failed to write document to {file_path}: {e}")
        return {
            "status": "error",
            "file_path": file_path,
            "error": str(e),
        }


def read_document_file(filename: str) -> dict:
    """Read a document file from the DOCUMENTS_PATH directory.

    Args:
        filename: The filename to read (e.g., "high-risk-ports_v1.md").

    Returns:
        dict with status, content, and file_path.
    """
    file_path = os.path.join(DOCUMENTS_PATH, filename)
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
        file_size = os.path.getsize(file_path)
        logger.info(f"Read document from {file_path} ({file_size} bytes)")
        return {
            "status": "success",
            "content": content,
            "file_path": file_path,
            "filename": filename,
            "file_size": file_size,
        }
    except Exception as e:
        logger.error(f"Failed to read document from {file_path}: {e}")
        return {
            "status": "error",
            "file_path": file_path,
            "error": str(e),
        }


def sync_document_to_qdrant(content: str, filename: str, document_type: str, source: str = None) -> dict:
    """Full sync: delete old entries, write file, and report status.

    Combines delete + write into a single operation for convenience.
    The VectorDBSyncAgent should then call `ingest_document` on the
    written file to complete the Qdrant upload via the RAG pipeline.

    Args:
        content: The markdown content to write.
        filename: The filename to write to in DOCUMENTS_PATH.
        document_type: The document_type to delete from Qdrant before writing.
        source: Optional source identifier (defaults to filename).

    Returns:
        dict with combined status of delete + write operations.
    """
    source = source or filename
    timestamp = datetime.now(timezone.utc).isoformat()

    # Step 1: Delete old entries
    delete_result = delete_qdrant_documents_by_type(document_type)

    # Step 2: Write new file
    write_result = write_document_to_file(content, filename)

    overall_status = "success"
    if delete_result["status"] == "error" and write_result["status"] == "error":
        overall_status = "failed"
    elif delete_result["status"] == "error" or write_result["status"] == "error":
        overall_status = "partial"

    return {
        "status": overall_status,
        "document_type": document_type,
        "filename": filename,
        "file_path": write_result.get("file_path", ""),
        "delete_result": delete_result,
        "write_result": write_result,
        "sync_timestamp": timestamp,
        "message": f"Sync {overall_status}: deleted old '{document_type}' entries, wrote new content to '{filename}'. "
                   f"Call ingest_document on '{write_result.get('file_path', filename)}' to complete Qdrant upload.",
    }


def _split_markdown_chunks(content: str, chunk_size: int = 2048, chunk_overlap: int = 400) -> list:
    """Split markdown content into chunks by headers, respecting size limits.

    Returns list of dicts with 'text' and 'header' keys.
    """
    # Split by markdown headers (# ## ###)
    header_pattern = re.compile(r"^(#{1,3})\s+(.+)$", re.MULTILINE)
    sections = []
    last_end = 0
    current_header = "Document"

    for match in header_pattern.finditer(content):
        if match.start() > last_end:
            text = content[last_end : match.start()].strip()
            if text:
                sections.append({"text": text, "header": current_header})
        current_header = match.group(2).strip()
        last_end = match.end()

    # Remaining content after last header
    remaining = content[last_end:].strip()
    if remaining:
        sections.append({"text": remaining, "header": current_header})

    # If no headers found, treat whole content as one section
    if not sections:
        sections = [{"text": content.strip(), "header": "Document"}]

    # Split oversized sections
    chunks = []
    for section in sections:
        text = section["text"]
        header = section["header"]
        if len(text) <= chunk_size:
            chunks.append({"text": text, "header": header})
        else:
            # Split by chunk_size with overlap
            start = 0
            while start < len(text):
                end = min(start + chunk_size, len(text))
                chunks.append({"text": text[start:end], "header": header})
                start = end - chunk_overlap
                if start + chunk_overlap >= len(text):
                    break

    return chunks


def _get_embeddings(texts: list) -> list:
    """Call OpenAI-compatible embedding API to get vectors for a list of texts."""
    import httpx

    url = f"{OPENAI_EMBEDDING_API_ENDPOINT}/embeddings"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {OPENAI_EMBEDDING_API_KEY}",
    }

    response = httpx.post(
        url,
        headers=headers,
        json={"model": OPENAI_EMBEDDING_MODEL, "input": texts},
        timeout=60.0,
    )
    response.raise_for_status()
    data = response.json()
    return [item["embedding"] for item in data["data"]]


def reingest_content_to_qdrant(content: str, document_type: str, source_filename: str = None) -> dict:
    """Delete old Qdrant entries and re-upload new content directly to Qdrant.

    Unlike sync_document_to_qdrant, this does NOT write to DOCUMENTS_PATH.
    It chunks the content, embeds it, and uploads vectors directly to Qdrant.

    Args:
        content: The markdown content to upload.
        document_type: The document_type to delete and re-upload
                       (e.g., "high-risk-ports_v1").
        source_filename: Optional source name for metadata
                         (default: document_type + ".md").

    Returns:
        dict with status, chunks uploaded, and any errors.
    """
    try:
        import httpx
    except ImportError:
        return {"status": "error", "error": "httpx library not available"}

    source_filename = source_filename or f"{document_type}.md"
    timestamp = datetime.now(timezone.utc).isoformat()
    errors = []

    # Step 1: Delete old entries
    delete_result = delete_qdrant_documents_by_type(document_type)
    if delete_result["status"] == "error":
        errors.append(f"Delete failed: {delete_result.get('error', 'unknown')}")

    # Step 2: Chunk the content
    chunks = _split_markdown_chunks(content)
    if not chunks:
        return {
            "status": "error",
            "error": "No chunks produced from content",
            "delete_result": delete_result,
        }

    logger.info(f"Split content into {len(chunks)} chunks for document_type='{document_type}'")

    # Step 3: Get embeddings
    try:
        chunk_texts = [c["text"] for c in chunks]
        embeddings = _get_embeddings(chunk_texts)
    except Exception as e:
        logger.error(f"Embedding API call failed: {e}")
        return {
            "status": "error",
            "error": f"Embedding failed: {e}",
            "delete_result": delete_result,
            "chunks_prepared": len(chunks),
        }

    # Step 4: Upload to Qdrant
    headers = {"Content-Type": "application/json"}
    if QDRANT_API_KEY:
        headers["api-key"] = QDRANT_API_KEY

    points = []
    for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
        points.append({
            "id": str(uuid.uuid4()),
            "vector": embedding,
            "payload": {
                "text": chunk["text"],
                "source": "filesystem",
                "source_type": "localfilesystem",
                "file_name": source_filename,
                "file_type": "md",
                "header": chunk["header"],
                "chunk_index": i,
                "document_type": document_type,
                "ingestion_timestamp": timestamp,
            },
        })

    try:
        client = httpx.Client(timeout=60.0)
        response = client.put(
            f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points",
            headers=headers,
            json={"points": points},
        )
        response.raise_for_status()
        qdrant_result = response.json()
        logger.info(
            f"Uploaded {len(points)} points to Qdrant for document_type='{document_type}'"
        )
    except Exception as e:
        logger.error(f"Qdrant upload failed: {e}")
        return {
            "status": "error",
            "error": f"Qdrant upload failed: {e}",
            "delete_result": delete_result,
            "chunks_prepared": len(chunks),
            "embeddings_generated": len(embeddings),
        }

    status = "success" if not errors else "partial"
    return {
        "status": status,
        "document_type": document_type,
        "source_filename": source_filename,
        "chunks_uploaded": len(points),
        "delete_result": delete_result,
        "sync_timestamp": timestamp,
        "errors": errors,
        "message": f"Re-ingested {len(points)} chunks for document_type='{document_type}' "
                   f"directly to Qdrant (no file written to disk).",
    }
