package auth

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/diaryai/server/internal/httpx"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

type Service struct {
	pool      *pgxpool.Pool
	jwtSecret []byte
	jwtTTL    time.Duration
}

func New(pool *pgxpool.Pool, jwtSecret []byte, jwtTTL time.Duration) *Service {
	return &Service{pool: pool, jwtSecret: jwtSecret, jwtTTL: jwtTTL}
}

func (s *Service) Routes(r chi.Router) {
	r.Post("/register", s.handleRegister)
	r.Post("/login", s.handleLogin)
	r.Post("/login/verify", s.handleLoginVerify)
}

// --- DTO ---

type registerRequest struct {
	Login     string          `json:"login"`
	AuthKey   string          `json:"auth_key"`  // base64
	KDFSalt   string          `json:"kdf_salt"`  // base64
	KDFParams json.RawMessage `json:"kdf_params"`
}

type loginRequest struct {
	Login string `json:"login"`
}

type loginResponse struct {
	KDFSalt   string          `json:"kdf_salt"`
	KDFParams json.RawMessage `json:"kdf_params"`
}

type loginVerifyRequest struct {
	Login   string `json:"login"`
	AuthKey string `json:"auth_key"` // base64
}

type loginVerifyResponse struct {
	Token  string `json:"token"`
	UserID string `json:"user_id"`
}

// --- handlers ---

func (s *Service) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_json", err.Error())
		return
	}
	login := normalizeLogin(req.Login)
	if !validLogin(login) {
		httpx.WriteError(w, http.StatusBadRequest, "bad_login", "login must be 3-64 chars, [a-z0-9_.-]")
		return
	}
	authKey, err := base64.StdEncoding.DecodeString(req.AuthKey)
	if err != nil || len(authKey) < 16 {
		httpx.WriteError(w, http.StatusBadRequest, "bad_auth_key", "auth_key must be base64 of >=16 bytes")
		return
	}
	salt, err := base64.StdEncoding.DecodeString(req.KDFSalt)
	if err != nil || len(salt) < 16 {
		httpx.WriteError(w, http.StatusBadRequest, "bad_salt", "kdf_salt must be base64 of >=16 bytes")
		return
	}
	if len(req.KDFParams) == 0 {
		httpx.WriteError(w, http.StatusBadRequest, "bad_params", "kdf_params required")
		return
	}

	hash, err := bcrypt.GenerateFromPassword(authKey, bcrypt.DefaultCost)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "hash_failed", "failed to hash auth key")
		return
	}

	id := uuid.New()
	_, err = s.pool.Exec(r.Context(), `
		INSERT INTO users (id, login, auth_key_hash, kdf_salt, kdf_params)
		VALUES ($1, $2, $3, $4, $5)
	`, id, login, string(hash), salt, req.KDFParams)
	if err != nil {
		if isUniqueViolation(err) {
			httpx.WriteError(w, http.StatusConflict, "login_taken", "login already exists")
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}

	token, err := issueToken(s.jwtSecret, s.jwtTTL, id)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "jwt_failed", err.Error())
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, loginVerifyResponse{Token: token, UserID: id.String()})
}

// /auth/login возвращает соль и параметры KDF для указанного логина,
// чтобы клиент мог детерминированно вывести auth_key и master_key.
// Чтобы не давать перечислять логины, для несуществующих возвращаем
// детерминированно сгенерированную "фейковую" соль (одинаковую для одного и того же логина).
func (s *Service) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_json", err.Error())
		return
	}
	login := normalizeLogin(req.Login)
	if !validLogin(login) {
		httpx.WriteError(w, http.StatusBadRequest, "bad_login", "invalid login format")
		return
	}

	var salt []byte
	var params json.RawMessage
	err := s.pool.QueryRow(r.Context(),
		`SELECT kdf_salt, kdf_params FROM users WHERE login = $1`, login,
	).Scan(&salt, &params)

	if errors.Is(err, pgx.ErrNoRows) {
		// Возвращаем псевдо-соль, чтобы не палить существование логина.
		salt = pseudoSalt(s.jwtSecret, login)
		params = defaultKDFParams()
	} else if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}

	httpx.WriteJSON(w, http.StatusOK, loginResponse{
		KDFSalt:   base64.StdEncoding.EncodeToString(salt),
		KDFParams: params,
	})
}

func (s *Service) handleLoginVerify(w http.ResponseWriter, r *http.Request) {
	var req loginVerifyRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_json", err.Error())
		return
	}
	login := normalizeLogin(req.Login)
	authKey, err := base64.StdEncoding.DecodeString(req.AuthKey)
	if err != nil || len(authKey) < 16 {
		httpx.WriteError(w, http.StatusBadRequest, "bad_auth_key", "invalid auth_key")
		return
	}

	var id uuid.UUID
	var hash string
	err = s.pool.QueryRow(r.Context(),
		`SELECT id, auth_key_hash FROM users WHERE login = $1`, login,
	).Scan(&id, &hash)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.WriteError(w, http.StatusUnauthorized, "bad_credentials", "invalid login or password")
		return
	} else if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(hash), authKey); err != nil {
		httpx.WriteError(w, http.StatusUnauthorized, "bad_credentials", "invalid login or password")
		return
	}

	token, err := issueToken(s.jwtSecret, s.jwtTTL, id)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "jwt_failed", err.Error())
		return
	}
	httpx.WriteJSON(w, http.StatusOK, loginVerifyResponse{Token: token, UserID: id.String()})
}

// --- helpers ---

func normalizeLogin(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

func validLogin(s string) bool {
	if len(s) < 3 || len(s) > 64 {
		return false
	}
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z':
		case r >= '0' && r <= '9':
		case r == '_' || r == '.' || r == '-':
		default:
			return false
		}
	}
	return true
}

func isUniqueViolation(err error) bool {
	return err != nil && strings.Contains(err.Error(), "23505")
}

// defaultKDFParams — параметры по умолчанию для отдачи на несуществующие логины,
// чтобы фронт не падал. Реальные пользователи получают свои сохранённые параметры.
func defaultKDFParams() json.RawMessage {
	return json.RawMessage(`{"algo":"argon2id","memory_kib":65536,"iterations":3,"parallelism":1,"key_len":32}`)
}

// Контекст для будущих обработчиков
var _ = context.Background
