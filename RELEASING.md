# Releasing

`release.yml` builds both miners, attaches them to the release and writes
`SHA256SUMS.txt` over every asset it finds there. The one step it cannot do is sign,
so that happens locally afterwards.

1. Tag and push, or run the workflow manually to publish to the `nightly` tag. Let it
   finish green.

2. Download what the workflow published, so the signature covers the same bytes users
   get:

   ```bash
   gh release download <tag> -D dist
   cd dist
   ```

3. Check the sums file covers every asset, then verify them:

   ```bash
   cat SHA256SUMS.txt
   sha256sum -c SHA256SUMS.txt
   ```

4. Sign the sums file. This is deliberately not in CI: a key held in CI secrets could be
   used by anyone who compromised the repository, which would make the signature
   meaningless.

   ```bash
   gpg --armor --detach-sign SHA256SUMS.txt
   gh release upload <tag> SHA256SUMS.txt.asc --clobber
   ```

5. Confirm the published signature verifies:

   ```bash
   gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
   ```

Signing key: `5C2C FA03 0397 FCD7 63F1  A97B F878 8EFB 40E7 50E5`

If signing prompts fail with an ioctl error, the shell has no tty for the passphrase
prompt. `export GPG_TTY=$(tty)` fixes it.
