# Client-Side Encryption

Encrypt sensitive content (passwords, keys, notes) so that even the server never sees the plaintext. Decryption happens entirely in the browser when a user enters a shared passphrase.

## Quick Start

1. Open `index.html` in your browser (locally or hosted)
2. Use Section 2 to encrypt your secret with a passphrase
3. Copy the generated HTML snippet into your web page
4. Share the passphrase with the recipient through a separate channel

## Files

| File | Purpose |
|------|---------|
| `client-encrypt.js` | Encryption/decryption library |
| `index.html` | Demo page with encrypt tool + live decrypt example |

## How It Works

```
1. You enter plaintext + passphrase in the encrypt tool
2. Tool generates a base64 blob (salt + IV + ciphertext)
3. You paste the blob into any web page as HTML
4. When clicked, the page prompts for passphrase and decrypts in-browser
5. Server only ever sees the encrypted blob - never the plaintext
```

## Installation

### Option 1: Host the Script

1. Upload `client-encrypt.js` to your web server
2. Include it in your HTML:
   ```html
   <script src="/path/to/client-encrypt.js"></script>
   ```

### Option 2: Inline in Page

For a single page, paste the entire `client-encrypt.js` content in a `<script>` tag.

### Option 3: Use the Demo Page

Host `index.html` and `client-encrypt.js` together. The demo page includes both the encryption tool and working examples.

## Usage

Add encrypted blocks to any HTML page:

```html
<div class="encrypted-secret" data-encrypted="YOUR_BASE64_BLOB_HERE">
  Click to reveal password
</div>
```

The script auto-initializes on page load. Clicking the block prompts for the passphrase.

## Security Details

| Property | Value |
|----------|-------|
| Algorithm | AES-256-GCM (authenticated encryption) |
| Key Derivation | PBKDF2-SHA256, 310,000 iterations |
| Salt | 128-bit random per encryption |
| IV | 96-bit random per encryption |
| Auth Tag | 128-bit (GCM default) |

### What's Protected

- Server never sees plaintext or passphrase
- Each encryption produces unique ciphertext (random salt + IV)
- Tampering detection via GCM authentication tag
- Brute-force resistant via high PBKDF2 iteration count

### What's NOT Protected

- Passphrase strength is your responsibility
- Anyone with the passphrase can decrypt
- No key rotation or expiration mechanism
- Decrypted content visible in browser DOM/memory

### Appropriate Use Cases

- Streaming service passwords shared with family
- WiFi passwords for guests
- Non-critical API keys
- Personal notes you want encrypted at rest

### NOT Appropriate For

- Banking credentials
- Cryptocurrency keys
- Anything where compromise = major harm
- Secrets that must remain secret even if passphrase leaks

## API Reference

```javascript
// Encrypt plaintext with passphrase
const blob = await SecureContent.encrypt('my secret', 'passphrase');

// Decrypt blob with passphrase
const plaintext = await SecureContent.decrypt(blob, 'passphrase');

// Re-initialize click handlers (after dynamic content load)
SecureContent.initDecryptBlocks();

// View configuration
console.log(SecureContent.CONFIG);
```

## Customization

### Styling Encrypted Blocks

The default styles are inline. Override with CSS:

```css
.encrypted-secret {
  background: #fff3e0;
  border: 1px solid #ff9800;
  padding: 15px;
  cursor: pointer;
}

.encrypted-secret:hover {
  background: #ffe0b2;
}

.decrypted-content {
  background: #e8f5e9;
  border: 1px solid #4caf50;
  padding: 10px;
  margin-top: 8px;
  font-family: monospace;
}
```

### Custom Prompt UI

Replace the default `prompt()` by overriding the click handler:

```javascript
document.querySelectorAll('.encrypted-secret').forEach(block => {
  block.onclick = async function() {
    const passphrase = await myCustomPasswordModal();
    if (!passphrase) return;

    try {
      const plaintext = await SecureContent.decrypt(
        this.dataset.encrypted,
        passphrase
      );
      // Display plaintext your way
    } catch (e) {
      // Handle error your way
    }
  };
});
```

## Browser Support

Requires Web Crypto API support:
- Chrome 37+
- Firefox 34+
- Safari 11+
- Edge 12+

All modern browsers supported. No IE11 support.

## License

MIT License
