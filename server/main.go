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

// --- Structs for /validate (single word) ---
type validationRequest struct {
	Word string `json:"word"`
}
type validationResponse struct {
	Valid bool   `json:"valid"`
	Error string `json:"error,omitempty"`
}

// --- Structs for /get-challenge ---
type challengeResponse struct {
	Challenge string `json:"challenge"`
	Error     string `json:"error,omitempty"`
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
			return strings.TrimSpace(string(txt)), nil
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

	prompt := fmt.Sprintf("Is the following an actual, single, common English word? Answer with only 'yes' or 'no'. Word: %s", req.Word)
	response, err := generateGeminiContent(ctx, model, prompt)
	if err != nil {
		log.Printf("Failed to validate word: %v", err)
		json.NewEncoder(w).Encode(validationResponse{Valid: false, Error: "Error processing word validation"})
		return
	}

	isValid := strings.ToLower(response) == "yes"
	json.NewEncoder(w).Encode(validationResponse{Valid: isValid})
}