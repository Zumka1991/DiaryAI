package sync

import (
	"encoding/base64"
	"errors"
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

type Service struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool}
}

func (s *Service) Routes(r chi.Router) {
	r.Post("/push", s.handlePush)
	r.Get("/pull", s.handlePull)
}

// --- DTO ---

type entryDTO struct {
	ID         string  `json:"id"`
	Ciphertext string  `json:"ciphertext"`           // base64
	Nonce      string  `json:"nonce"`                // base64
	UpdatedAt  string  `json:"updated_at"`           // RFC3339
	DeletedAt  *string `json:"deleted_at,omitempty"` // RFC3339
	DeviceID   string  `json:"device_id"`
}

type pushRequest struct {
	Entries []entryDTO `json:"entries"`
}

type pushResponse struct {
	Accepted int `json:"accepted"`
}

type pullResponse struct {
	Entries []entryDTO `json:"entries"`
	HasMore bool       `json:"has_more"`
	NextSince string   `json:"next_since,omitempty"`
}

// --- handlers ---

const maxPushBatch = 500
const maxPullBatch = 500

func (s *Service) handlePush(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, "no_user", "no user in context")
		return
	}

	var req pushRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_json", err.Error())
		return
	}
	if len(req.Entries) == 0 {
		httpx.WriteJSON(w, http.StatusOK, pushResponse{Accepted: 0})
		return
	}
	if len(req.Entries) > maxPushBatch {
		httpx.WriteError(w, http.StatusBadRequest, "batch_too_large",
			"max "+strconv.Itoa(maxPushBatch)+" entries per push")
		return
	}

	tx, err := s.pool.Begin(r.Context())
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	accepted := 0
	for i, e := range req.Entries {
		id, err := uuid.Parse(e.ID)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_id",
				"entry["+strconv.Itoa(i)+"]: invalid uuid")
			return
		}
		ct, err := base64.StdEncoding.DecodeString(e.Ciphertext)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_ciphertext",
				"entry["+strconv.Itoa(i)+"]: invalid base64")
			return
		}
		nonce, err := base64.StdEncoding.DecodeString(e.Nonce)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_nonce",
				"entry["+strconv.Itoa(i)+"]: invalid nonce")
			return
		}
		updatedAt, err := time.Parse(time.RFC3339Nano, e.UpdatedAt)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_updated_at",
				"entry["+strconv.Itoa(i)+"]: invalid time")
			return
		}
		var deletedAt *time.Time
		if e.DeletedAt != nil {
			t, err := time.Parse(time.RFC3339Nano, *e.DeletedAt)
			if err != nil {
				httpx.WriteError(w, http.StatusBadRequest, "bad_deleted_at",
					"entry["+strconv.Itoa(i)+"]: invalid time")
				return
			}
			deletedAt = &t
		}
		if e.DeviceID == "" {
			httpx.WriteError(w, http.StatusBadRequest, "bad_device_id",
				"entry["+strconv.Itoa(i)+"]: device_id required")
			return
		}

		// Last-write-wins: вставляем или обновляем, если входящий updated_at новее.
		ct2, err := tx.Exec(r.Context(), `
			INSERT INTO entries (id, user_id, ciphertext, nonce, updated_at, deleted_at, device_id)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			ON CONFLICT (id) DO UPDATE SET
				ciphertext = EXCLUDED.ciphertext,
				nonce      = EXCLUDED.nonce,
				updated_at = EXCLUDED.updated_at,
				deleted_at = EXCLUDED.deleted_at,
				device_id  = EXCLUDED.device_id
			WHERE entries.user_id = EXCLUDED.user_id
			  AND entries.updated_at < EXCLUDED.updated_at
		`, id, uid, ct, nonce, updatedAt, deletedAt, e.DeviceID)
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

	since := time.Time{} // если не указан — отдаём всё с начала времён
	if v := r.URL.Query().Get("since"); v != "" {
		t, err := time.Parse(time.RFC3339Nano, v)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "bad_since", "since must be RFC3339")
			return
		}
		since = t
	}

	rows, err := s.pool.Query(r.Context(), `
		SELECT id, ciphertext, nonce, updated_at, deleted_at, device_id
		FROM entries
		WHERE user_id = $1 AND updated_at > $2
		ORDER BY updated_at ASC
		LIMIT $3
	`, uid, since, maxPullBatch+1)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		httpx.WriteError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	defer rows.Close()

	out := make([]entryDTO, 0, maxPullBatch)
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
		dto := entryDTO{
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
