"""Tests for provider/model defaults derived from local environment config."""

import pytest

from web.components.sidebar import (
    _PROVIDER_API_KEY_ENV,
    _PROVIDER_KEYS,
    _default_model_index,
    _default_provider_index,
)


@pytest.fixture(autouse=True)
def clear_provider_environment(monkeypatch):
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    monkeypatch.delenv("QUICK_THINK_LLM", raising=False)
    monkeypatch.delenv("DEEP_THINK_LLM", raising=False)
    for env_name in _PROVIDER_API_KEY_ENV.values():
        monkeypatch.delenv(env_name, raising=False)


def test_provider_defaults_to_first_option_without_configuration():
    assert _default_provider_index() == 0


def test_only_configured_api_key_selects_its_provider(monkeypatch):
    monkeypatch.setenv("DEEPSEEK_API_KEY", "configured")
    assert _PROVIDER_KEYS[_default_provider_index()] == "deepseek"


def test_explicit_provider_wins_over_detected_api_key(monkeypatch):
    monkeypatch.setenv("DEEPSEEK_API_KEY", "configured")
    monkeypatch.setenv("LLM_PROVIDER", "openai")
    assert _PROVIDER_KEYS[_default_provider_index()] == "openai"


def test_multiple_api_keys_keep_existing_default(monkeypatch):
    monkeypatch.setenv("DEEPSEEK_API_KEY", "configured")
    monkeypatch.setenv("OPENAI_API_KEY", "configured")
    assert _default_provider_index() == 0


@pytest.mark.parametrize(
    ("mode", "expected_index"),
    [("quick", 0), ("deep", 1)],
)
def test_deepseek_defaults_to_current_v4_models(mode, expected_index):
    values = ["deepseek-v4-flash", "deepseek-v4-pro", "deepseek-chat"]
    assert _default_model_index("deepseek", mode, values) == expected_index


def test_explicit_model_overrides_deepseek_default(monkeypatch):
    values = ["deepseek-v4-flash", "deepseek-chat"]
    monkeypatch.setenv("QUICK_THINK_LLM", "deepseek-chat")
    assert _default_model_index("deepseek", "quick", values) == 1
