#include <stddef.h>

int sodium_init(void);
int crypto_box_keypair(unsigned char *public_key, unsigned char *private_key);
int crypto_scalarmult_base(unsigned char *public_key, const unsigned char *private_key);
int crypto_box_seal(unsigned char *ciphertext, const unsigned char *message,
                    unsigned long long message_length, const unsigned char *public_key);
int crypto_box_seal_open(unsigned char *message, const unsigned char *ciphertext,
                         unsigned long long ciphertext_length, const unsigned char *public_key,
                         const unsigned char *private_key);
