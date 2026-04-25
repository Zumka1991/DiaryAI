package auth

import (
	"crypto/hmac"
	"crypto/sha256"
)

// pseudoSalt деривирует детерминированную "псевдо-соль" для несуществующих логинов.
// Это нужно, чтобы /auth/login отвечал одинаково для существующих и несуществующих логинов
// и не давал атакующему перечислить аккаунты. Один и тот же логин всегда даёт одну и ту же соль.
func pseudoSalt(secret []byte, login string) []byte {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte("diaryai-pseudo-salt-v1"))
	mac.Write([]byte(login))
	sum := mac.Sum(nil)
	return sum[:16]
}
