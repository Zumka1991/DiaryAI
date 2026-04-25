-- Категории также шифруются на клиенте: name + color + sort_order упакованы в payload.
CREATE TABLE categories (
    id           uuid PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ciphertext   bytea NOT NULL,
    nonce        bytea NOT NULL,
    updated_at   timestamptz NOT NULL,
    deleted_at   timestamptz,
    device_id    text NOT NULL
);

CREATE INDEX categories_user_updated_idx ON categories (user_id, updated_at);
