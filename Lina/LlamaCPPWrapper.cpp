#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include "../../llama.cpp/include/llama.h"

// Global variables for model management
static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static llama_sampler* g_sampler = nullptr;
static std::mutex g_mutex;
static std::atomic<bool> g_is_generating(false);
static std::atomic<bool> g_should_stop(false);

// Callback function pointer for streaming tokens
typedef void (*TokenCallback)(const char* token);
static TokenCallback g_token_callback = nullptr;

// MARK: - Model Loading Functions
extern "C" bool load_model(const char* model_path, int n_ctx, int n_threads, int n_gpu_layers) {
    std::lock_guard<std::mutex> lock(g_mutex);

    // Free existing model if any
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_free_model(g_model);
        g_model = nullptr;
    }

    // Initialize llama.cpp backend
    ggml_backend_load_all();

    // Load model
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = n_gpu_layers;

    g_model = llama_model_load_from_file(model_path, model_params);
    if (!g_model) {
        std::cerr << "Failed to load model from: " << model_path << std::endl;
        return false;
    }

    // Create context
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = n_ctx;
    ctx_params.n_threads = n_threads;
    ctx_params.n_batch = 512;
    ctx_params.no_perf = false;

    g_ctx = llama_init_from_model(g_model, ctx_params);
    if (!g_ctx) {
        std::cerr << "Failed to create context" << std::endl;
        llama_free_model(g_model);
        g_model = nullptr;
        return false;
    }

    // Initialize sampler chain (greedy sampling for now)
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = false;
    g_sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_greedy());

    std::cout << "✅ Model loaded successfully: " << model_path << std::endl;
    return true;
}

extern "C" void unload_model() {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_free_model(g_model);
        g_model = nullptr;
    }
}

extern "C" bool is_model_loaded() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_model != nullptr && g_ctx != nullptr && g_sampler != nullptr;
}

// MARK: - Streaming Generation with Callback
extern "C" void set_token_callback(TokenCallback callback) {
    g_token_callback = callback;
}

extern "C" void generate_text_streaming(const char* prompt, int max_tokens, float temperature,
                                       float top_p, int top_k, float repeat_penalty) {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (!g_model || !g_ctx || !g_sampler) {
        if (g_token_callback) {
            g_token_callback("Error: No model loaded");
        }
        return;
    }

    if (g_is_generating) {
        if (g_token_callback) {
            g_token_callback("Error: Already generating");
        }
        return;
    }

    g_is_generating = true;
    g_should_stop = false;

    // Get vocab
    const llama_vocab* vocab = llama_model_get_vocab(g_model);

    // Tokenize prompt
    std::string prompt_str(prompt);
    const int n_prompt = -llama_tokenize(vocab, prompt_str.c_str(), prompt_str.size(), NULL, 0, true, true);
    
    std::vector<llama_token> prompt_tokens(n_prompt);
    if (llama_tokenize(vocab, prompt_str.c_str(), prompt_str.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        if (g_token_callback) {
            g_token_callback("Error: Failed to tokenize prompt");
        }
        g_is_generating = false;
        return;
    }

    // Prepare batch for prompt
    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());

    // Process prompt (prefill)
    if (llama_decode(g_ctx, batch)) {
        if (g_token_callback) {
            g_token_callback("Error: Failed to process prompt");
        }
        g_is_generating = false;
        return;
    }

    // Main generation loop - token by token
    int n_decode = 0;
    for (int n_pos = prompt_tokens.size(); n_pos < prompt_tokens.size() + max_tokens; n_pos++) {
        if (g_should_stop) {
            break;
        }

        // Sample next token
        llama_token new_token_id = llama_sampler_sample(g_sampler, g_ctx, -1);

        // Check for end of generation
        if (llama_vocab_is_eog(vocab, new_token_id)) {
            break;
        }

        // Convert token to text piece
        char buf[256];
        int n = llama_token_to_piece(vocab, new_token_id, buf, sizeof(buf), 0, true);
        if (n < 0) {
            if (g_token_callback) {
                g_token_callback("Error: Failed to convert token");
            }
            break;
        }

        // CRITICAL: Immediately send token to callback (like llama.cpp's printf + fflush)
        if (g_token_callback) {
            std::string token_str(buf, n);
            g_token_callback(token_str.c_str());
        }

        // Prepare next batch with the new token
        batch = llama_batch_get_one(&new_token_id, 1);

        // Decode the new token
        if (llama_decode(g_ctx, batch)) {
            if (g_token_callback) {
                g_token_callback("\nError: Failed to decode token");
            }
            break;
        }

        n_decode++;
    }

    g_is_generating = false;
}

// Legacy synchronous generation (kept for compatibility)
extern "C" const char* generate_text(const char* prompt, int max_tokens, float temperature,
                                   float top_p, int top_k, float repeat_penalty) {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (!g_model || !g_ctx || !g_sampler) {
        return strdup("Error: No model loaded");
    }

    if (g_is_generating) {
        return strdup("Error: Already generating");
    }

    g_is_generating = true;
    g_should_stop = false;

    // Get vocab
    const llama_vocab* vocab = llama_model_get_vocab(g_model);

    // Tokenize prompt
    std::string prompt_str(prompt);
    const int n_prompt = -llama_tokenize(vocab, prompt_str.c_str(), prompt_str.size(), NULL, 0, true, true);
    
    std::vector<llama_token> prompt_tokens(n_prompt);
    if (llama_tokenize(vocab, prompt_str.c_str(), prompt_str.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        g_is_generating = false;
        return strdup("Error: Failed to tokenize prompt");
    }

    // Prepare batch for prompt
    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());

    // Process prompt
    if (llama_decode(g_ctx, batch)) {
        g_is_generating = false;
        return strdup("Error: Failed to process prompt");
    }

    // Generate response
    std::string response;
    for (int i = 0; i < max_tokens; ++i) {
        if (g_should_stop) {
            break;
        }

        // Sample next token
        llama_token new_token_id = llama_sampler_sample(g_sampler, g_ctx, -1);

        // Check for end of generation
        if (llama_vocab_is_eog(vocab, new_token_id)) {
            break;
        }

        // Convert token to text
        char buf[256];
        int n = llama_token_to_piece(vocab, new_token_id, buf, sizeof(buf), 0, true);
        if (n < 0) {
            break;
        }
        
        response.append(buf, n);

        // Prepare next batch
        batch = llama_batch_get_one(&new_token_id, 1);

        // Decode
        if (llama_decode(g_ctx, batch)) {
            break;
        }
    }

    g_is_generating = false;
    return strdup(response.c_str());
}

extern "C" bool is_generating() {
    return g_is_generating;
}

extern "C" void cancel_generation() {
    g_is_generating = false;
}

// MARK: - Model Information Functions
extern "C" int get_model_vocab_size() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_model) return 0;
    return llama_n_vocab(g_model);
}

extern "C" int get_model_context_length() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ctx) return 0;
    return llama_n_ctx(g_ctx);
}

extern "C" const char* get_model_name() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_model) return strdup("");

    // Try to get model name from metadata
    std::string name;
    for (int i = 0; i < llama_model_meta_count(g_model); ++i) {
        char key[256];
        char value[256];
        int key_len = llama_model_meta_key_by_index(g_model, i, key, sizeof(key));
        int value_len = llama_model_meta_val_str_by_index(g_model, i, value, sizeof(value));

        if (key_len > 0 && value_len > 0 && std::string(key, key_len) == "general.name") {
            name = std::string(value, value_len);
            break;
        }
    }

    return strdup(name.c_str());
}

// MARK: - Memory Management
extern "C" void free_string(const char* str) {
    if (str) {
        free((void*)str);
    }
}
