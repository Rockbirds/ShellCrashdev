/* Read a password from standard input and emit a salted SHA-512 crypt hash.
 * The password is never passed on the command line or written to a file. */
#include <stdio.h>
#include <string.h>

extern char *crypt(const char *, const char *);

int main(void) {
    static const char alphabet[] = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    unsigned char random_bytes[16];
    char password[512];
    char salt[21] = "$6$";
    FILE *random_file;
    char *newline;
    char *hash;
    size_t i;
    volatile char *secret;

    if (!fgets(password, sizeof password, stdin)) return 1;
    newline = strchr(password, '\n');
    if (!newline || newline == password) return 1;
    *newline = '\0';

    random_file = fopen("/dev/urandom", "rb");
    if (!random_file) return 1;
    if (fread(random_bytes, 1, sizeof random_bytes, random_file) != sizeof random_bytes) {
        fclose(random_file);
        return 1;
    }
    fclose(random_file);
    for (i = 0; i < sizeof random_bytes; i++) salt[3 + i] = alphabet[random_bytes[i] & 63];
    salt[19] = '$';
    salt[20] = '\0';

    hash = crypt(password, salt);
    secret = (volatile char *)password;
    for (i = 0; i < sizeof password; i++) secret[i] = 0;
    if (!hash || strncmp(hash, "$6$", 3) != 0) return 1;
    return puts(hash) == EOF;
}
