package auth

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/diaryai/server/internal/httpx"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type ctxKey string

const userIDKey ctxKey = "user_id"

type Claims struct {
	UserID string `json:"uid"`
	jwt.RegisteredClaims
}

func issueToken(secret []byte, ttl time.Duration, userID uuid.UUID) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID: userID.String(),
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
			Subject:   userID.String(),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return tok.SignedString(secret)
}

func parseToken(secret []byte, raw string) (uuid.UUID, error) {
	claims := &Claims{}
	_, err := jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return secret, nil
	})
	if err != nil {
		return uuid.Nil, err
	}
	return uuid.Parse(claims.UserID)
}

// Middleware проверяет JWT в Authorization: Bearer <token> и кладёт user_id в контекст.
func Middleware(secret []byte) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := r.Header.Get("Authorization")
			if !strings.HasPrefix(h, "Bearer ") {
				httpx.WriteError(w, http.StatusUnauthorized, "no_token", "missing bearer token")
				return
			}
			uid, err := parseToken(secret, strings.TrimPrefix(h, "Bearer "))
			if err != nil {
				httpx.WriteError(w, http.StatusUnauthorized, "bad_token", "invalid or expired token")
				return
			}
			ctx := context.WithValue(r.Context(), userIDKey, uid)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// UserID извлекает user_id из контекста (после Middleware).
func UserID(ctx context.Context) (uuid.UUID, bool) {
	v, ok := ctx.Value(userIDKey).(uuid.UUID)
	return v, ok
}
