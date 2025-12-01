//
//  Lina-Bridging-Header.h
//  Lina v1
//
//  C++ bridging header for llama.cpp integration
//

#ifndef Lina_Bridging_Header_h
#define Lina_Bridging_Header_h

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Model Loading Functions
bool load_model(const char* model_path, int n_ctx, int n_threads, int n_gpu_layers);
void unload_model();
bool is_model_loaded();

// MARK: - Token Callback for Streaming
typedef void (*TokenCallback)(const char* token);
void set_token_callback(TokenCallback callback);

// MARK: - Text Generation Functions
// Streaming generation with callback (like llama.cpp's printf + fflush approach)
void generate_text_streaming(const char* prompt, int max_tokens, float temperature,
                            float top_p, int top_k, float repeat_penalty);

// Legacy synchronous generation
const char* generate_text(const char* prompt, int max_tokens, float temperature,
                         float top_p, int top_k, float repeat_penalty);

bool is_generating();
void cancel_generation();

// MARK: - Model Information Functions
int get_model_vocab_size();
int get_model_context_length();
const char* get_model_name();

// MARK: - Memory Management
void free_string(const char* str);

#ifdef __cplusplus
}
#endif

#endif /* Lina_Bridging_Header_h */
