/**
 * Client-Side Encryption for Wiki.js
 *
 * AES-256-GCM encryption with PBKDF2 key derivation.
 * Works entirely in the browser using Web Crypto API.
 *
 * Usage:
 *   // Encrypt (offline tool)
 *   const blob = await SecureContent.encrypt('my secret', 'passphrase');
 *
 *   // Decrypt (in wiki page)
 *   const plaintext = await SecureContent.decrypt(blob, 'passphrase');
 *
 * @license MIT
 */

const SecureContent = (function() {
  'use strict';

  // Configuration
  const CONFIG = {
    algorithm: 'AES-GCM',
    keyLength: 256,
    ivLength: 12,       // 96 bits recommended for GCM
    saltLength: 16,     // 128 bits
    iterations: 310000, // OWASP 2023 recommendation for PBKDF2-SHA256
    tagLength: 128      // Authentication tag length in bits
  };

  /**
   * Derive a key from passphrase using PBKDF2
   */
  async function deriveKey(passphrase, salt) {
    const encoder = new TextEncoder();
    const keyMaterial = await crypto.subtle.importKey(
      'raw',
      encoder.encode(passphrase),
      'PBKDF2',
      false,
      ['deriveKey']
    );

    return crypto.subtle.deriveKey(
      {
        name: 'PBKDF2',
        salt: salt,
        iterations: CONFIG.iterations,
        hash: 'SHA-256'
      },
      keyMaterial,
      { name: CONFIG.algorithm, length: CONFIG.keyLength },
      false,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Encrypt plaintext with passphrase
   * @param {string} plaintext - Text to encrypt
   * @param {string} passphrase - User's passphrase
   * @returns {string} Base64-encoded encrypted blob (salt + iv + ciphertext)
   */
  async function encrypt(plaintext, passphrase) {
    const encoder = new TextEncoder();

    // Generate random salt and IV
    const salt = crypto.getRandomValues(new Uint8Array(CONFIG.saltLength));
    const iv = crypto.getRandomValues(new Uint8Array(CONFIG.ivLength));

    // Derive key from passphrase
    const key = await deriveKey(passphrase, salt);

    // Encrypt
    const ciphertext = await crypto.subtle.encrypt(
      { name: CONFIG.algorithm, iv: iv, tagLength: CONFIG.tagLength },
      key,
      encoder.encode(plaintext)
    );

    // Combine: salt (16) + iv (12) + ciphertext (variable)
    const combined = new Uint8Array(salt.length + iv.length + ciphertext.byteLength);
    combined.set(salt, 0);
    combined.set(iv, salt.length);
    combined.set(new Uint8Array(ciphertext), salt.length + iv.length);

    // Return as base64
    return btoa(String.fromCharCode(...combined));
  }

  /**
   * Decrypt blob with passphrase
   * @param {string} blob - Base64-encoded encrypted data
   * @param {string} passphrase - User's passphrase
   * @returns {string} Decrypted plaintext
   * @throws {Error} If passphrase is wrong or data is corrupted
   */
  async function decrypt(blob, passphrase) {
    const decoder = new TextDecoder();

    // Decode base64
    const combined = Uint8Array.from(atob(blob), c => c.charCodeAt(0));

    // Extract salt, iv, and ciphertext
    const salt = combined.slice(0, CONFIG.saltLength);
    const iv = combined.slice(CONFIG.saltLength, CONFIG.saltLength + CONFIG.ivLength);
    const ciphertext = combined.slice(CONFIG.saltLength + CONFIG.ivLength);

    // Derive key from passphrase
    const key = await deriveKey(passphrase, salt);

    // Decrypt
    try {
      const plaintext = await crypto.subtle.decrypt(
        { name: CONFIG.algorithm, iv: iv, tagLength: CONFIG.tagLength },
        key,
        ciphertext
      );
      return decoder.decode(plaintext);
    } catch (e) {
      throw new Error('Decryption failed - wrong passphrase or corrupted data');
    }
  }

  /**
   * Initialize encrypted blocks on page
   * Call this after DOM is ready to enable click-to-decrypt functionality
   */
  function initDecryptBlocks() {
    document.querySelectorAll('.encrypted-secret').forEach(block => {
      if (block.dataset.initialized) return;
      block.dataset.initialized = 'true';

      block.style.cursor = 'pointer';
      block.addEventListener('click', async function() {
        const encrypted = this.dataset.encrypted;
        if (!encrypted) {
          alert('No encrypted data found');
          return;
        }

        const passphrase = prompt('Enter passphrase to decrypt:');
        if (!passphrase) return;

        try {
          const plaintext = await decrypt(encrypted, passphrase);

          // Create a styled decrypted content area
          const content = document.createElement('div');
          content.className = 'decrypted-content';
          content.style.cssText = 'background: #e8f5e9; border: 1px solid #4caf50; padding: 10px; border-radius: 4px; margin-top: 8px; font-family: monospace; white-space: pre-wrap; word-break: break-all;';
          content.textContent = plaintext;

          // Add a "hide" button
          const hideBtn = document.createElement('button');
          hideBtn.textContent = 'Hide';
          hideBtn.style.cssText = 'margin-left: 10px; cursor: pointer; padding: 2px 8px;';
          hideBtn.onclick = (e) => {
            e.stopPropagation();
            content.remove();
            this.querySelector('.decrypted-content')?.remove();
          };
          content.appendChild(hideBtn);

          // Remove any existing decrypted content
          this.querySelector('.decrypted-content')?.remove();
          this.appendChild(content);

        } catch (e) {
          alert(e.message);
        }
      });
    });
  }

  // Auto-initialize when DOM is ready
  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', initDecryptBlocks);
    } else {
      // DOM already loaded (script loaded dynamically)
      initDecryptBlocks();
    }
  }

  // Public API
  return {
    encrypt,
    decrypt,
    initDecryptBlocks,
    CONFIG
  };
})();

// Export for module systems (Node.js, ES modules)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = SecureContent;
}
