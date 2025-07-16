package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
)

// --- Structs for /validate (natural language input) ---
type validationRequest struct {
	Sentence     string `json:"sentence"`
	WordCount    int    `json:"word_count"`
	RequiredWord string `json:"required_word,omitempty"`
}
type validationResponse struct {
	Valid      bool   `json:"valid"`
	Comment    string `json:"comment"`
	NextPrompt string `json:"next_prompt,omitempty"`
	Error      string `json:"error,omitempty"`
}

// --- Structs for /get-challenge ---
type challengeResponse struct {
	Challenge string `json:"challenge"`
	Error     string `json:"error,omitempty"`
}

// --- Structs for /get-prompt ---
type promptRequest struct {
	WordCount int `json:"word_count"`
}
type promptResponse struct {
	Prompt string `json:"prompt"`
	Error  string `json:"error,omitempty"`
}

// --- Structs for /validate-sentence ---
type sentenceValidationRequest struct {
	Challenge string `json:"challenge"`
	Sentence  string `json:"sentence"`
}
type sentenceValidationResponse struct {
	Valid bool   `json:"valid"`
	Error string `json:"error,omitempty"`
}

func main() {
	http.HandleFunc("/validate", validateHandler)
	http.HandleFunc("/get-challenge", challengeHandler)
	http.HandleFunc("/validate-sentence", validateSentenceHandler)
	http.HandleFunc("/get-prompt", promptHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	fmt.Printf("Server starting on port %s...\n", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func getGeminiClient(ctx context.Context) (*genai.GenerativeModel, error) {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY environment variable not set")
	}

	client, err := genai.NewClient(ctx, option.WithAPIKey(apiKey))
	if err != nil {
		return nil, fmt.Errorf("error creating Gemini client: %v", err)
	}

	modelName := os.Getenv("GEMINI_MODEL_NAME_LITE")
	if modelName == "" {
		modelName = "gemini-1.5-flash"
	}
	return client.GenerativeModel(modelName), nil
}

func generateGeminiContent(ctx context.Context, model *genai.GenerativeModel, prompt string) (string, error) {
	resp, err := model.GenerateContent(ctx, genai.Text(prompt))
	if err != nil {
		return "", err
	}
	if len(resp.Candidates) > 0 && len(resp.Candidates[0].Content.Parts) > 0 {
		if txt, ok := resp.Candidates[0].Content.Parts[0].(genai.Text); ok {
			response := strings.TrimSpace(string(txt))
			// Clean up the response to ensure it's valid JSON
			// Remove any markdown code blocks if present
			response = strings.TrimPrefix(response, "```json")
			response = strings.TrimSuffix(response, "```")
			response = strings.TrimSpace(response)
			return response, nil
		}
	}
	return "", fmt.Errorf("empty or invalid response from Gemini")
}

func challengeHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		http.Error(w, "Only GET method is allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx := context.Background()
	model, err := getGeminiClient(ctx)
	if err != nil {
		log.Println(err)
		json.NewEncoder(w).Encode(challengeResponse{Error: "Server configuration error"})
		return
	}

	prompt := "Give me a single, interesting, intermediate-level English word or idiom. Respond with only the word or idiom itself, nothing else."
	challenge, err := generateGeminiContent(ctx, model, prompt)
	if err != nil {
		log.Printf("Failed to generate challenge: %v", err)
		json.NewEncoder(w).Encode(challengeResponse{Error: "Failed to generate challenge"})
		return
	}

	json.NewEncoder(w).Encode(challengeResponse{Challenge: challenge})
}

func validateSentenceHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		http.Error(w, "Only POST method is allowed", http.StatusMethodNotAllowed)
		return
	}

	var req sentenceValidationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		json.NewEncoder(w).Encode(sentenceValidationResponse{Valid: false, Error: "Invalid request body"})
		return
	}

	ctx := context.Background()
	model, err := getGeminiClient(ctx)
	if err != nil {
		log.Println(err)
		json.NewEncoder(w).Encode(sentenceValidationResponse{Valid: false, Error: "Server configuration error"})
		return
	}

	prompt := fmt.Sprintf("You are a strict English teacher. Does the following sentence correctly and naturally use the given English word or idiom? The sentence must be grammatically correct. Answer with only 'yes' or 'no'.\n\nIdiom/Word: '%s'\n\nSentence: '%s'", req.Challenge, req.Sentence)
	
	response, err := generateGeminiContent(ctx, model, prompt)
	if err != nil {
		log.Printf("Failed to validate sentence: %v", err)
		json.NewEncoder(w).Encode(sentenceValidationResponse{Valid: false, Error: "Failed to validate sentence"})
		return
	}

	isValid := strings.ToLower(response) == "yes"
	json.NewEncoder(w).Encode(sentenceValidationResponse{Valid: isValid})
}

func validateHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	
	if r.Method != http.MethodPost {
		http.Error(w, "Only POST method is allowed", http.StatusMethodNotAllowed)
		return
	}

	var req validationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		json.NewEncoder(w).Encode(validationResponse{Valid: false, Error: "Invalid request body"})
		return
	}

	ctx := context.Background()
	model, err := getGeminiClient(ctx)
	if err != nil {
		log.Println(err)
		json.NewEncoder(w).Encode(validationResponse{Valid: false, Error: "Server configuration error"})
		return
	}

	requiredWordPrompt := ""
	if req.RequiredWord != "" {
		requiredWordPrompt = fmt.Sprintf("\nRequired word to use: %s", req.RequiredWord)
	}

	prompt := fmt.Sprintf(`You are Rin (凛), a haughty aristocratic young lady who looks down on commoners' poor English skills.

Task: Evaluate this English input from a commoner
Required word count: %d
Input: "%s"%s

Rules:
1. Check if it has EXACTLY %d words (count carefully! Count the actual words they wrote)
2. Check if it's grammatically correct English (identify specific errors if any)
3. If the previous prompt mentioned a specific word to use (like "happyという単語を使って"), check if they used it (case-insensitive)
4. All conditions must be true for valid=true
5. IMPORTANT: Ignore capitalization errors - treat "i love cats" the same as "I love cats"

When evaluating, identify:
- The actual word count (not what they intended)
- Any grammar mistakes (be specific: wrong verb form, missing articles, etc.) BUT NOT capitalization
- Whether required words are missing (check case-insensitively)

Respond with ONLY this JSON format:
{"valid": true/false, "comment": "your comment", "next_prompt": "next challenge prompt"}

For comments, speak as Rin in Japanese:
- If valid: Reluctantly acknowledge but still be condescending (e.g. "ふん、偶然でしょうけど...今回は認めてあげるわ。")
- If wrong word count: Tell them the exact count and mock them (e.g. "それ、5語じゃなくて3語ですわよ。数も数えられないの？")
- If bad grammar: Point out the specific error and mock them (e.g. "「I likes」じゃなくて「I like」ですわ。基本的な動詞活用もできないの？")
- If missing required word: Point it out (e.g. "「happy」を使えって言ったでしょう？聞いてなかったの？")
- NOTE: Don't comment on capitalization - "i am happy" is fine, just as good as "I am happy"

For next_prompt (ONLY if valid=true and word count < 7):
- Give the next challenge in Rin's condescending tone in Japanese
- Choose any word count between 3-7 (be creative and unpredictable!)
- Include a simple English word they must use (like: cat, dog, happy, good, like, want, eat, go, big, small)
- Include the exact number in your prompt
- Examples: 
  "ふん、では次は5語で「happy」という単語を使って話してみなさい。"
  "3語なんて簡単すぎたわね。じゃあ6語で「like」を使ってみなさい。"
  "まぐれね。次は4語で「cat」を使って文を作りなさい。できるかしら？"
- If word count >= 7, set next_prompt to empty string

Be creative and vary the word counts!`, req.WordCount, req.Sentence, requiredWordPrompt, req.WordCount, req.WordCount)
	
	response, err := generateGeminiContent(ctx, model, prompt)
	if err != nil {
		log.Printf("Failed to validate: %v", err)
		json.NewEncoder(w).Encode(validationResponse{Valid: false, Comment: "サーバーの調子が悪いようね。もう一度試しなさい。"})
		return
	}

	// Log the raw response for debugging
	log.Printf("Gemini response: %s", response)
	
	// Parse JSON response
	var result validationResponse
	if err := json.Unmarshal([]byte(response), &result); err != nil {
		log.Printf("Failed to parse response: %v, raw response: %s", err, response)
		json.NewEncoder(w).Encode(validationResponse{Valid: false, Comment: "なんだか変な応答が返ってきたわ。もう一度やり直しなさい。"})
		return
	}

	// Ensure comment is not empty
	if result.Comment == "" {
		if result.Valid {
			result.Comment = "ふむ...なかなかやりますわね。"
		} else {
			result.Comment = "あら、その英語おかしいですわよ。"
		}
	}
	
	// Log the final response
	log.Printf("Sending response: %+v", result)

	json.NewEncoder(w).Encode(result)
}