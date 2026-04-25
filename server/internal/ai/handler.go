package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/diaryai/server/internal/auth"
	"github.com/diaryai/server/internal/httpx"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	dailyAnalyzeLimit = 3
	defaultModel      = "anthropic/claude-haiku-4.5"
	openRouterURL     = "https://openrouter.ai/api/v1/chat/completions"
	maxOutputTokens   = 800
)

type Service struct {
	pool             *pgxpool.Pool
	openRouterAPIKey string
	httpClient       *http.Client
}

func New(pool *pgxpool.Pool, openRouterAPIKey string) *Service {
	return &Service{
		pool:             pool,
		openRouterAPIKey: openRouterAPIKey,
		httpClient:       &http.Client{Timeout: 60 * time.Second},
	}
}

func (s *Service) Routes(r chi.Router) {
	r.Post("/analyze", s.handleAnalyze)
}

// --- DTO ---

type entryDTO struct {
	Date     string  `json:"date"`     // RFC3339 или дата
	Title    string  `json:"title"`
	Category *string `json:"category,omitempty"`
	Text     string  `json:"text"`
}

type analyzeRequest struct {
	FocusEntry     entryDTO   `json:"focus_entry"`
	ContextEntries []entryDTO `json:"context_entries"`
	Model          string     `json:"model,omitempty"`
}

type analyzeResponse struct {
	Analysis      string `json:"analysis"`
	Used          int    `json:"used"`
	DailyLimit    int    `json:"daily_limit"`
}

// --- handler ---

func (s *Service) handleAnalyze(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, "no_user", "no user in context")
		return
	}

	if s.openRouterAPIKey == "" {
		httpx.WriteError(w, http.StatusServiceUnavailable, "ai_unavailable",
			"AI пока недоступен (на сервере не настроен ключ OpenRouter)")
		return
	}

	var req analyzeRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_json", err.Error())
		return
	}
	if req.FocusEntry.Text == "" {
		httpx.WriteError(w, http.StatusBadRequest, "empty_focus", "focus_entry.text is empty")
		return
	}

	// Rate-limit: считаем использование за сегодня (UTC).
	today := time.Now().UTC().Format("2006-01-02")
	used, err := s.getUsage(r.Context(), uid.String(), today)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	if used >= dailyAnalyzeLimit {
		httpx.WriteJSON(w, http.StatusTooManyRequests, map[string]any{
			"error":       "Достигнут дневной лимит анализов",
			"code":        "daily_limit_reached",
			"used":        used,
			"daily_limit": dailyAnalyzeLimit,
		})
		return
	}

	model := req.Model
	if model == "" {
		model = defaultModel
	}

	analysis, err := s.callOpenRouter(r.Context(), model, buildPrompt(req))
	if err != nil {
		slog.Error("openrouter call failed", "err", err)
		httpx.WriteError(w, http.StatusBadGateway, "upstream_error", err.Error())
		return
	}

	if err := s.incUsage(r.Context(), uid.String(), today); err != nil {
		// логируем, но ответ юзеру отдаём — анализ-то сделан
		slog.Error("inc usage failed", "err", err)
	}

	httpx.WriteJSON(w, http.StatusOK, analyzeResponse{
		Analysis:   analysis,
		Used:       used + 1,
		DailyLimit: dailyAnalyzeLimit,
	})
}

// --- usage ---

func (s *Service) getUsage(ctx context.Context, uid, day string) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx,
		`SELECT analyze_count FROM ai_usage WHERE user_id = $1 AND day = $2`, uid, day,
	).Scan(&n)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return n, err
}

func (s *Service) incUsage(ctx context.Context, uid, day string) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO ai_usage (user_id, day, analyze_count)
		VALUES ($1, $2, 1)
		ON CONFLICT (user_id, day) DO UPDATE SET analyze_count = ai_usage.analyze_count + 1
	`, uid, day)
	return err
}

// --- OpenRouter ---

type orMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type orRequest struct {
	Model     string      `json:"model"`
	Messages  []orMessage `json:"messages"`
	MaxTokens int         `json:"max_tokens,omitempty"`
}

type orResponse struct {
	Choices []struct {
		Message orMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func (s *Service) callOpenRouter(ctx context.Context, model, userPrompt string) (string, error) {
	body := orRequest{
		Model: model,
		Messages: []orMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		MaxTokens: maxOutputTokens,
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", openRouterURL, bytes.NewReader(raw))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+s.openRouterAPIKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("HTTP-Referer", "https://diaryai.ru")
	req.Header.Set("X-Title", "DiaryAI")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("openrouter %d: %s", resp.StatusCode, string(respBody))
	}

	var parsed orResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return "", fmt.Errorf("parse response: %w", err)
	}
	if parsed.Error != nil {
		return "", errors.New(parsed.Error.Message)
	}
	if len(parsed.Choices) == 0 {
		return "", errors.New("empty response from model")
	}
	return parsed.Choices[0].Message.Content, nil
}

// --- prompt ---

const systemPrompt = `Ты — эмпатичный собеседник и наблюдатель, помогающий человеку вести дневник.
Принципы:
— тёплый, человеческий тон, без морализаторства;
— ВНИМАТЕЛЬНО смотри на даты записей. Контекстные записи могут быть и ДО, и ПОСЛЕ фокусной.
  Если фокусная запись — старая, упоминай что было ПОТОМ ("через неделю ты написал…"),
  как сложилось то, что тогда волновало;
— ищи связи и паттерны: повторяющиеся темы, прогресс, противоречия;
— говори о времени конкретно: "вчера", "три дня назад", "неделей позже",
  ориентируйся по датам, а не на абстрактном "недавно";
— не давай медицинских или психотерапевтических диагнозов;
— не оценивай морально;
— отвечай на русском языке;
— укладывайся в 3–5 коротких абзацев.`

func buildPrompt(r analyzeRequest) string {
	var b bytes.Buffer
	b.WriteString("ФОКУСНАЯ ЗАПИСЬ (которую анализируем):\n")
	writeEntry(&b, r.FocusEntry)

	if len(r.ContextEntries) > 0 {
		b.WriteString("\nКОНТЕКСТНЫЕ ЗАПИСИ (отсортированы хронологически — старые сверху, новые снизу).\n")
		b.WriteString("Некоторые могут быть ДО фокусной, некоторые — ПОСЛЕ. Сравнивай даты.\n")
		for i, e := range r.ContextEntries {
			fmt.Fprintf(&b, "\n--- запись %d ---\n", i+1)
			writeEntry(&b, e)
		}
	}
	b.WriteString("\nПроанализируй фокусную запись с учётом всего контекста. ")
	b.WriteString("Учитывай хронологию и упоминай конкретные даты или относительное время. ")
	b.WriteString("Дай поддержку и наблюдения.")
	return b.String()
}

func writeEntry(b *bytes.Buffer, e entryDTO) {
	if e.Date != "" {
		fmt.Fprintf(b, "Дата: %s\n", e.Date)
	}
	if e.Title != "" {
		fmt.Fprintf(b, "Заголовок: %s\n", e.Title)
	}
	if e.Category != nil && *e.Category != "" {
		fmt.Fprintf(b, "Категория: %s\n", *e.Category)
	}
	fmt.Fprintf(b, "Текст: %s\n", e.Text)
}
