import base64
import json
import logging
import re
from pathlib import Path

from openai import OpenAI

from config import OPENAI_API_KEY
logger = logging.getLogger(__name__)

EXTRACTION_PROMPT = """You are reading a delivery invoice image.
Extract exactly these fields and return valid JSON only (no markdown):
{
  "customer_name": "full customer or recipient name",
  "customer_phone": "phone number as shown, digits and + only if present",
  "invoice_number": "invoice or order number"
}
If a field is missing or unreadable, use an empty string for that field.
Do not invent data that is not visible on the invoice."""

MIME_BY_EXT = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".gif": "image/gif",
}


def _mime_for_path(path: Path) -> str:
    return MIME_BY_EXT.get(path.suffix.lower(), "image/jpeg")


def _parse_json_content(content: str) -> dict:
    text = content.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("Model response was not a JSON object")
    return {
        "customer_name": str(data.get("customer_name", "")).strip(),
        "customer_phone": str(data.get("customer_phone", "")).strip(),
        "invoice_number": str(data.get("invoice_number", "")).strip(),
    }


def extract_invoice_fields(image_path: Path) -> dict:
    image_bytes = image_path.read_bytes()
    b64 = base64.standard_b64encode(image_bytes).decode("ascii")
    mime = _mime_for_path(image_path)
    data_url = f"data:{mime};base64,{b64}"

    client = OpenAI(api_key=OPENAI_API_KEY)
    logger.info("Calling OpenAI vision for invoice: %s", image_path.name)

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": EXTRACTION_PROMPT},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }
        ],
        response_format={"type": "json_object"},
        max_tokens=500,
    )

    content = response.choices[0].message.content or "{}"
    fields = _parse_json_content(content)
    logger.info(
        "Extracted invoice fields — number=%s, customer=%s",
        fields["invoice_number"] or "(empty)",
        fields["customer_name"] or "(empty)",
    )
    return fields
