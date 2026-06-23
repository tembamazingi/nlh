#!/usr/bin/env python3
"""
scripts/llm_refine.py — transformers backend for nlh LLM refinement.

Reads raw transcript from stdin, returns refined transcript on stdout.
System prompt is read from NLH_LLM_SYSTEM_PROMPT env var or uses the default.
Model path is read from NLH_LLM_MODEL_PATH env var.

Usage:
    echo "raw transcript" | python3 scripts/llm_refine.py

Exit codes:
    0 — success, refined text on stdout
    1 — error (model not found, inference failure, etc.)
"""

import sys
import os


DEFAULT_SYSTEM_PROMPT = (
    "You are a transcript cleaner. Remove filler words (um, uh, like, you know), "
    "false starts, and self-corrections. Fix punctuation and capitalisation. "
    "Preserve all technical terms, proper nouns, and code identifiers exactly as spoken. "
    "Output only the cleaned transcript — no commentary, no explanations."
)


def main() -> int:
    model_path = os.environ.get("NLH_LLM_MODEL_PATH", "")
    system_prompt = os.environ.get("NLH_LLM_SYSTEM_PROMPT", DEFAULT_SYSTEM_PROMPT)

    if not model_path:
        print("nlh llm_refine: NLH_LLM_MODEL_PATH not set", file=sys.stderr)
        return 1

    # Read transcript from stdin
    raw_transcript = sys.stdin.read().strip()
    if not raw_transcript:
        return 1

    try:
        from transformers import pipeline, AutoTokenizer, AutoModelForCausalLM
        import torch
    except ImportError:
        print("nlh llm_refine: transformers not installed. Run: pip install transformers torch", file=sys.stderr)
        return 1

    try:
        tokenizer = AutoTokenizer.from_pretrained(model_path, local_files_only=True)
        model = AutoModelForCausalLM.from_pretrained(
            model_path,
            local_files_only=True,
            torch_dtype=torch.float16 if torch.cuda.is_available() else torch.float32,
            device_map="auto",
        )
        pipe = pipeline(
            "text-generation",
            model=model,
            tokenizer=tokenizer,
        )

        prompt = f"{system_prompt}\n\nTranscript:\n{raw_transcript}\n\nCleaned:"
        result = pipe(
            prompt,
            max_new_tokens=512,
            do_sample=False,
            temperature=None,
            top_p=None,
        )
        generated = result[0]["generated_text"]
        # Extract the part after "Cleaned:"
        if "Cleaned:" in generated:
            refined = generated.split("Cleaned:", 1)[1].strip()
        else:
            refined = generated[len(prompt):].strip()

        print(refined)
        return 0

    except Exception as e:
        print(f"nlh llm_refine: inference error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
