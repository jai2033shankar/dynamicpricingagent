#!/bin/bash
# ─── Ollama Model Setup Script ───────────────────────────────────────────────
# Pulls required models for the DynamicPricingEngine platform.
# Run this script after installing Ollama: https://ollama.com/download

set -e

echo "═══════════════════════════════════════════════════════"
echo "  DynamicPricingEngine — Ollama Model Setup"
echo "═══════════════════════════════════════════════════════"

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "❌ Ollama is not installed."
    echo "   Install from: https://ollama.com/download"
    exit 1
fi

# Check if Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "⚠️  Ollama is not running. Starting..."
    ollama serve &
    sleep 3
fi

echo ""
echo "📦 Pulling required models..."
echo ""

# 1. LLM for intent extraction and reasoning
echo "🧠 [1/3] Pulling Mistral 7B (intent extraction + reasoning)..."
ollama pull mistral:7b
echo "✅ Mistral 7B ready"

# 2. Alternative: Gemma 3 (lighter weight)
echo ""
echo "🧠 [2/3] Pulling Gemma 3 (alternative LLM)..."
ollama pull gemma3:4b
echo "✅ Gemma 3 ready"

# 3. Embedding model
echo ""
echo "📐 [3/3] Pulling nomic-embed-text (embeddings)..."
ollama pull nomic-embed-text
echo "✅ Embeddings model ready"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ All models pulled successfully!"
echo ""
echo "  Available models:"
ollama list
echo ""
echo "  Health check:"
curl -s http://localhost:11434/api/tags | python3 -m json.tool 2>/dev/null || echo "  Run 'ollama serve' to start"
echo "═══════════════════════════════════════════════════════"
