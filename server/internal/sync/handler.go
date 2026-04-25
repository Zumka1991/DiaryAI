package sync

import (
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/diaryai/server/internal/auth"
	"github.com/diaryai/server/internal/httpx"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Service синхронизирует одну таблицу, в которой строки — opaque blob'ы:
// id, user_id, ciphertext, nonce, updated_at, deleted_at, device_id.
// Используется и для entries, и для categories — структура одинаковая.
type Service struct {
	pool      *pgxpool.Pool
	tableName string
	listKey   string // ключ массива в JSON: "entries" / "categories"
}

func New(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool, tableName: "entries", listKey: "entries"}
}

// NewFor создаёт сервис для произвольной таблицы (например "categories").
func NewFor(pool *pgxpool.Pool, table, listKey string) *Service {
	return &Service{pool: pool, tableName: table, listKey: listKey}
}

func (s *Service) Routes(r chi.Router) {
	r.Post("/push", s.handlePush)
	r.Get("/pull", s.handlePull)
}

// --- DTO ---

type itemDTO struct {
	ID         string  `json:"id"`
	Ciphertext string  `json:"ciphertext"`
	Nonce      string  `json:"nonce"`
	UpdatedAt  string  `json:"updated_at"`
	DeletedAt  *string `json:"deleted_at,omitempty"`
	DeviceID   string  `json:"device_id"`
}

type pushResponse struct {
	Accepted int `json:"accepted"`
}

type pullResponse struct {
	Entries   []itemDTO `json:"entries"`
	HasMore   bool      `json:"has_more"`
	NextSince string    `json:"next_since,omitempty"`
}

const (
	maxPushBatch = 500
	maxPullBatch = 500
)

func (s *Service) handlePush(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, "no_user", "no user in context")
		return
	}

	// Принимаем массив либо в "entries", либо в нашем listKey — оба варианта,
	// чтобы клиент не путался при общем коде синка.
	var raw map[string]any
	if err := httpx.DecodeJSON(r, &raw); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_json", err.Error())
		return
	}
	listAny, ok := raw[s.listKey].([]any)
	if !ok {
		listAny, _ = raw["entries"].([]any)
	}
	if len(listAny) == 0 {
		httpx.WriteJSON(w, http.StatusOK, pushResponse{Accepted: 0})
		return
	}
	if len(listAny) > maxPushBatch {
		httpx.WriteError(w, http.StatusBadRequest, "batch_too_large",
			"max "+strconv.Itoa(maxPushBatch)+" items per push")
		return
	}

	tx, err := s.pool.Begin(r.Context())
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	insertSQL := fmt.Sprintf(`
		INSERT INTO %s (id, user_id, ciphertext, nonce, updated_at, deleted_at, device_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (id) DO UPDATE SET
			ciphertext = EXCLUDED.ciphertext,
			nonce      = EXCLUDED.nonce,
			updated_at = EXCLUDED.updated_at,
			deleted_at = EXCLUDED.deleted_at,
			device_id  = EXCLUDED.device_id
		WHERE %s.user_id = EXCLUDED.user_id
		  AND %s.updated_at < EXCLUDED.updated_at
	`, s.tableName, s.tableName, s.tableName)

	accepted := 0
	for i, raw := range listAny {
		m, ok := raw.(map[string]any)
		if !ok {
			httpx.WriteError(w, http.StatusBadRequest, "bad_item",
				"item["+strconv.Itoa(i)+"]: not an object")
			return
		}
		idStr, _ := m["id"].(string)
		id, err := uuid.Parse(idStr)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_id",
				"item["+strconv.Itoa(i)+"]: invalid uuid")
			return
		}
		ctStr, _ := m["ciphertext"].(string)
		ct, err := base64.StdEncoding.DecodeString(ctStr)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_ciphertext",
				"item["+strconv.Itoa(i)+"]: invalid base64")
			return
		}
		nonceStr, _ := m["nonce"].(string)
		nonce, err := base64.StdEncoding.DecodeString(nonceStr)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_nonce",
				"item["+strconv.Itoa(i)+"]: invalid nonce")
			return
		}
		updatedStr, _ := m["updated_at"].(string)
		updatedAt, err := time.Parse(time.RFC3339Nano, updatedStr)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_updated_at",
				"item["+strconv.Itoa(i)+"]: invalid time")
			return
		}
		var deletedAt *time.Time
		if delStr, hasDel := m["deleted_at"].(string); hasDel && delStr != "" {
			t, err := time.Parse(time.RFC3339Nano, delStr)
			if err != nil {
				httpx.WriteError(w, http.StatusBadRequest, "bad_deleted_at",
					"item["+strconv.Itoa(i)+"]: invalid time")
				return
			}
			deletedAt = &t
		}
		deviceID, _ := m["device_id"].(string)
		if deviceID == "" {
			httpx.WriteError(w, http.StatusBadRequest, "bad_device_id",
				"item["+strconv.Itoa(i)+"]: device_id required")
			return
		}

		ct2, err := tx.Exec(r.Context(), insertSQL,
			id, uid, ct, nonce, updatedAt, deletedAt, deviceID)
		if err != nil {
			httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
			return
		}
		if ct2.RowsAffected() > 0 {
			accepted++
		}
	}

	if err := tx.Commit(r.Context()); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	httpx.WriteJSON(w, http.StatusOK, pushResponse{Accepted: accepted})
}

func (s *Service) handlePull(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, "no_user", "no user in context")
		return
	}

	since := time.Time{}
	if v := r.URL.Query().Get("since"); v != "" {
		t, err := time.Parse(time.RFC3339Nano, v)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_since", "since must be RFC3339")
			return
		}
		since = t
	}

	selectSQL := fmt.Sprintf(`
		SELECT id, ciphertext, nonce, updated_at, deleted_at, device_id
		FROM %s
		WHERE user_id = $1 AND updated_at > $2
		ORDER BY updated_at ASC
		LIMIT $3
	`, s.tableName)

	rows, err := s.pool.Query(r.Context(), selectSQL, uid, since, maxPullBatch+1)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	defer rows.Close()

	out := make([]itemDTO, 0, maxPullBatch)
	for rows.Next() {
		var (
			id        uuid.UUID
			ct, nonce []byte
			updatedAt time.Time
			deletedAt *time.Time
			deviceID  string
		)
		if err := rows.Scan(&id, &ct, &nonce, &updatedAt, &deletedAt, &deviceID); err != nil {
			httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
			return
		}
		dto := itemDTO{
			ID:         id.String(),
			Ciphertext: base64.StdEncoding.EncodeToString(ct),
			Nonce:      base64.StdEncoding.EncodeToString(nonce),
			UpdatedAt:  updatedAt.Format(time.RFC3339Nano),
			DeviceID:   deviceID,
		}
		if deletedAt != nil {
			s := deletedAt.Format(time.RFC3339Nano)
			dto.DeletedAt = &s
		}
		out = append(out, dto)
	}

	hasMore := len(out) > maxPullBatch
	nextSince := ""
	if hasMore {
		out = out[:maxPullBatch]
		nextSince = out[len(out)-1].UpdatedAt
	}
	httpx.WriteJSON(w, http.StatusOK, pullResponse{
		Entries:   out,
		HasMore:   hasMore,
		NextSince: nextSince,
	})
}
