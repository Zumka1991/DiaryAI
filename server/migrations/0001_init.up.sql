CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Пользователи. Сервер НИКОГДА не видит пароль.
-- auth_key_hash = bcrypt(auth_key), где auth_key деривируется на клиенте из (login, password) через Argon2id.
-- kdf_salt и kdf_params отдаются клиенту при логине, чтобы он мог детерминированно повторить деривацию.
CREATE TABLE users (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    login           text NOT NULL UNIQUE,
    auth_key_hash   text NOT NULL,
    kdf_salt        bytea NOT NULL,
    kdf_params      jsonb NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX users_login_idx ON users (lower(login));

-- Записи дневника. Сервер хранит только зашифрованный блоб.
-- ciphertext содержит JSON {text, category, created_at, ...} зашифрованный master_key клиента.
CREATE TABLE entries (
    id           uuid PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ciphertext   bytea NOT NULL,
    nonce        bytea NOT NULL,
    updated_at   timestamptz NOT NULL,
    deleted_at   timestamptz,
    device_id    text NOT NULL
);

CREATE INDEX entries_user_updated_idx ON entries (user_id, updated_at);

-- Учёт ИИ-запросов на пользователя в день — нужен для anti-abuse rate limiting,
-- т.к. дефолтный AI-доступ бесплатный, но идёт через наш OpenRouter/Groq ключ.
CREATE TABLE ai_usage (
    user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day            date NOT NULL,
    analyze_count  int NOT NULL DEFAULT 0,
    transcribe_seconds int NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, day)
);
