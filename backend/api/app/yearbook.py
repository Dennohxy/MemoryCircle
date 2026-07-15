"""Constrained theme and contribution contracts for the graduation yearbook
pilot (docs/GRADUATION_YEARBOOK_DESIGN.md sections 4-5).

Everything here is deliberately a whitelist: fixed token keys, bundled
typography presets, enumerated layout variants, and typed contribution
payloads. No arbitrary CSS/HTML/fonts ever pass through this module.
"""

from __future__ import annotations

import re
from typing import Optional

HEX_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")

TYPOGRAPHY_PRESETS = {"formal_serif", "modern_sans", "classic_mixed"}
COVER_LAYOUTS = {"crest_centered", "photo_hero", "banner"}
HEADER_VARIANTS = {"logo_and_section", "section_only", "none"}
FOOTER_VARIANTS = {"event_and_page", "page_only", "none"}
SIGNATURE_STYLES = {"clean_script", "serif_caps", "modern_sans"}
PAGE_FORMATS = {"screen_portrait_3_4"}
BRAND_ASSET_KINDS = {"logo", "secondary_mark", "background", "cover"}

# Per-kind upload rules: (max bytes, min long edge px, max long edge px).
BRAND_ASSET_RULES = {
    "logo": (4 * 1024 * 1024, 400, 3000),
    "secondary_mark": (4 * 1024 * 1024, 400, 3000),
    "background": (10 * 1024 * 1024, 1600, 8000),
    "cover": (10 * 1024 * 1024, 1600, 8000),
}

GRADUATION_TOKENS_DEFAULT = {
    "schema_version": 1,
    "colors": {
        "primary": "#123A63",
        "secondary": "#E8EEF3",
        "accent": "#C9A227",
        "text": "#17202A",
        "background": "#FFFFFF",
    },
    "assets": {
        "logo_id": None,
        "secondary_mark_id": None,
        "cover_asset_id": None,
        "background_asset_id": None,
    },
    "typography": {
        "preset": "formal_serif",
        "heading_scale": "standard",
        "body_scale": "standard",
    },
    "cover": {"layout": "crest_centered", "overlay": "none", "show_date": True},
    "header": {"variant": "logo_and_section", "alignment": "center", "text": ""},
    "footer": {
        "variant": "event_and_page",
        "text": "",
        "show_page_number": True,
        "show_logo": False,
    },
    "page": {
        "format": "screen_portrait_3_4",
        "background": "solid",
        "photo_frame": "formal_white",
        "signature_style": "clean_script",
        "screen_safe_margin": 32,
        "print_safe_margin_mm": 12,
        "bleed_mm": 3,
    },
}

DEFAULT_CONSENT_TEXT = (
    "I agree that the name, photos, and messages I submit may be reviewed by "
    "the organizers and published in this event's digital yearbook. I can "
    "withdraw a pending submission while the campaign is open."
)

DEFAULT_CONTRIBUTION_SETTINGS = {
    "enabled_types": [
        "photo_memory",
        "graduate_profile",
        "dedication",
        "typed_signature",
    ],
    "per_guest_text_quota": 5,
    "profile_required_fields": ["full_name", "programme"],
}

CONTRIBUTION_TYPES = {
    "photo_memory",
    "graduate_profile",
    "dedication",
    "official_message",
    "typed_signature",
    "acknowledgement",
}

# Per-type text fields: name -> (max_length, required_by_default).
_PAYLOAD_FIELDS: dict[str, dict[str, tuple[int, bool]]] = {
    "photo_memory": {"caption": (280, False)},
    "graduate_profile": {
        "full_name": (160, True),
        "preferred_name": (80, False),
        "programme": (160, False),
        "honours": (160, False),
        "quote": (280, False),
        "future_plans": (280, False),
    },
    "dedication": {
        "message": (600, True),
        "from_name": (120, False),
        "recipient_label": (160, False),
    },
    "official_message": {
        "title": (160, False),
        "message": (2000, True),
        "author_name": (160, False),
        "author_role": (160, False),
    },
    "typed_signature": {
        "text": (80, True),
        "style": (40, False),
    },
    "acknowledgement": {
        "message": (600, True),
        "from_name": (120, False),
    },
}


def _relative_luminance(hex_color: str) -> float:
    channels = []
    for index in (1, 3, 5):
        value = int(hex_color[index:index + 2], 16) / 255.0
        channels.append(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4)
    r, g, b = channels
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(hex_a: str, hex_b: str) -> float:
    lum_a = _relative_luminance(hex_a)
    lum_b = _relative_luminance(hex_b)
    lighter, darker = max(lum_a, lum_b), min(lum_a, lum_b)
    return (lighter + 0.05) / (darker + 0.05)


def validate_theme_tokens(tokens: dict) -> tuple[dict, list[str]]:
    """Merges the given tokens over the graduation defaults, keeping only
    known keys, and returns (normalized_tokens, error_codes)."""
    errors: list[str] = []
    normalized = {
        "schema_version": 1,
        "colors": dict(GRADUATION_TOKENS_DEFAULT["colors"]),
        "assets": dict(GRADUATION_TOKENS_DEFAULT["assets"]),
        "typography": dict(GRADUATION_TOKENS_DEFAULT["typography"]),
        "cover": dict(GRADUATION_TOKENS_DEFAULT["cover"]),
        "header": dict(GRADUATION_TOKENS_DEFAULT["header"]),
        "footer": dict(GRADUATION_TOKENS_DEFAULT["footer"]),
        "page": dict(GRADUATION_TOKENS_DEFAULT["page"]),
    }
    colors = tokens.get("colors") or {}
    for name in normalized["colors"]:
        value = colors.get(name)
        if value is None:
            continue
        if not isinstance(value, str) or not HEX_COLOR.match(value):
            errors.append(f"theme.invalid_color.{name}")
        else:
            normalized["colors"][name] = value.upper()
    if contrast_ratio(normalized["colors"]["text"], normalized["colors"]["background"]) < 4.5:
        errors.append("theme.low_contrast")

    assets = tokens.get("assets") or {}
    for name in normalized["assets"]:
        if name in assets:
            value = assets[name]
            if value is not None and not isinstance(value, int):
                errors.append(f"theme.invalid_asset.{name}")
            else:
                normalized["assets"][name] = value

    typography = tokens.get("typography") or {}
    preset = typography.get("preset", normalized["typography"]["preset"])
    if preset not in TYPOGRAPHY_PRESETS:
        errors.append("theme.invalid_typography")
    else:
        normalized["typography"]["preset"] = preset

    cover = tokens.get("cover") or {}
    layout = cover.get("layout", normalized["cover"]["layout"])
    if layout not in COVER_LAYOUTS:
        errors.append("theme.invalid_cover_layout")
    else:
        normalized["cover"]["layout"] = layout
    if "show_date" in cover:
        normalized["cover"]["show_date"] = bool(cover["show_date"])

    header = tokens.get("header") or {}
    variant = header.get("variant", normalized["header"]["variant"])
    if variant not in HEADER_VARIANTS:
        errors.append("theme.invalid_header")
    else:
        normalized["header"]["variant"] = variant
    normalized["header"]["text"] = str(header.get("text", normalized["header"]["text"]))[:160]

    footer = tokens.get("footer") or {}
    variant = footer.get("variant", normalized["footer"]["variant"])
    if variant not in FOOTER_VARIANTS:
        errors.append("theme.invalid_footer")
    else:
        normalized["footer"]["variant"] = variant
    normalized["footer"]["text"] = str(footer.get("text", normalized["footer"]["text"]))[:160]
    if "show_page_number" in footer:
        normalized["footer"]["show_page_number"] = bool(footer["show_page_number"])

    page = tokens.get("page") or {}
    style = page.get("signature_style", normalized["page"]["signature_style"])
    if style not in SIGNATURE_STYLES:
        errors.append("theme.invalid_signature_style")
    else:
        normalized["page"]["signature_style"] = style

    return normalized, errors


def validate_contribution_payload(
    contribution_type: str,
    payload: dict,
    settings: Optional[dict] = None,
) -> tuple[dict, list[str]]:
    """Whitelists and length-checks a contribution payload; returns
    (clean_payload, error_codes)."""
    errors: list[str] = []
    settings = settings or {}
    if contribution_type not in CONTRIBUTION_TYPES:
        return {}, ["contribution.unknown_type"]
    spec = _PAYLOAD_FIELDS[contribution_type]
    required_overrides = set(settings.get("profile_required_fields") or []) \
        if contribution_type == "graduate_profile" else set()
    clean: dict = {}
    for field, (max_length, required) in spec.items():
        value = payload.get(field)
        if value is None or (isinstance(value, str) and not value.strip()):
            if required or field in required_overrides:
                errors.append(f"contribution.missing.{field}")
            continue
        if not isinstance(value, str):
            errors.append(f"contribution.invalid.{field}")
            continue
        value = value.strip()
        if len(value) > max_length:
            errors.append(f"contribution.too_long.{field}")
            continue
        clean[field] = value
    if contribution_type == "typed_signature":
        style = clean.get("style", "clean_script")
        if style not in SIGNATURE_STYLES:
            errors.append("contribution.invalid.style")
        else:
            clean["style"] = style
    if contribution_type == "graduate_profile" and isinstance(payload.get("photo_asset_id"), int):
        clean["photo_asset_id"] = payload["photo_asset_id"]
    return clean, errors
