#!/usr/bin/env node

/**
 * Wiki.js Asset Authentication Service
 *
 * Maps folder names to Wiki.js group permissions automatically:
 * - /secure-assets/managers/* → Requires user in "managers" group
 * - /secure-assets/vacation/* → Requires user in "vacation" group
 *
 * Usage: node asset-auth-service.js
 * Listens on: http://localhost:3002
 */

const express = require('express');
const { Pool } = require('pg');
const cookieParser = require('cookie-parser');
const jwt = require('jsonwebtoken');

const app = express();
app.use(cookieParser());

// Database connection
const pool = new Pool({
  host: 'localhost',
  database: 'wikijs',
  user: 'wikijs',
  password: 'wikijspassword',
  port: 5432
});

// JWT Public Key (loaded dynamically from database at startup)
let JWT_PUBLIC_KEY = null;

/**
 * Initialize JWT public key from Wiki.js database
 * Wiki.js uses RS256 (RSA) for JWT signing, so we need the public key
 */
async function initializeSecret() {
  try {
    const result = await pool.query(
      "SELECT value::text FROM settings WHERE key = 'certs'"
    );

    if (result.rows.length === 0) {
      throw new Error('certs not found in database');
    }

    const valueStr = result.rows[0].value;
    const certsData = JSON.parse(valueStr);
    JWT_PUBLIC_KEY = certsData.public;

    console.log('✓ JWT public key loaded from database');
  } catch (err) {
    console.error('❌ Failed to load JWT public key:', err.message);
    process.exit(1);
  }
}

// Test database connection on startup
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('❌ Database connection failed:', err.message);
    process.exit(1);
  } else {
    console.log('✓ Database connected');
  }
});

/**
 * Shared authentication logic
 */
async function authenticateRequest(req, res) {
  const groupName = req.params.groupName;
  const assetPath = req.params.assetPath || '';

  // Extract JWT from cookie
  const cookies = req.cookies || {};
  const jwtToken = cookies['jwt'];

  console.log(`[${new Date().toISOString()}] AUTH REQUEST:`);
  console.log(`  Group: ${groupName}`);
  console.log(`  Asset: ${assetPath}`);

  // Check if JWT cookie exists
  if (!jwtToken) {
    console.log(`  Result: ❌ DENIED (no JWT token)`);
    return res.status(403).send('No JWT token');
  }

  try {
    // Verify JWT signature using Wiki.js RSA public key
    // Wiki.js uses RS256 algorithm for JWT signing
    const decoded = jwt.verify(jwtToken, JWT_PUBLIC_KEY, {
      algorithms: ['RS256']
    });

    if (!decoded || !decoded.id) {
      console.log(`  Result: ❌ DENIED (invalid JWT payload)`);
      return res.status(403).send('Invalid JWT payload');
    }

    const userId = decoded.id;
    console.log(`  User ID from JWT: ${userId}`);
    console.log(`  Email from JWT: ${decoded.email}`);

    // Query to check if user is in the required group OR Administrators group
    // Checks for "Administrators" group (Wiki.js admin group)
    const result = await pool.query(`
      SELECT
        u.id as user_id,
        u.email as user_email,
        g.name as group_name
      FROM users u
      JOIN "userGroups" ug ON u.id = ug."userId"
      JOIN groups g ON ug."groupId" = g.id
      WHERE u.id = $1
        AND (g.name = $2 OR g.name = 'Administrators')
      LIMIT 1
    `, [userId, groupName]);

    if (result.rows.length > 0) {
      const user = result.rows[0];
      console.log(`  User: ${user.user_email}`);
      if (user.group_name === 'Administrators') {
        console.log(`  Result: ✅ ALLOWED (Administrator - full access)`);
      } else {
        console.log(`  Result: ✅ ALLOWED (in group "${groupName}")`);
      }
      return res.status(200).send('OK');
    } else {
      // Check if user exists but not in group
      const userCheck = await pool.query(`
        SELECT u.email
        FROM users u
        WHERE u.id = $1
      `, [userId]);

      if (userCheck.rows.length > 0) {
        console.log(`  User: ${userCheck.rows[0].email}`);
        console.log(`  Result: ❌ DENIED (not in group "${groupName}" or Administrators)`);
        return res.status(403).send(`Not in group "${groupName}" or Administrators`);
      } else {
        console.log(`  Result: ❌ DENIED (user not found)`);
        return res.status(403).send('User not found');
      }
    }
  } catch (err) {
    // JWT verification failed (invalid signature, expired, etc.)
    if (err.name === 'JsonWebTokenError') {
      console.log(`  Result: ❌ DENIED (JWT verification failed: ${err.message})`);
      return res.status(403).send('Invalid JWT signature');
    } else if (err.name === 'TokenExpiredError') {
      console.log(`  Result: ❌ DENIED (JWT expired)`);
      return res.status(403).send('JWT expired');
    }

    // Database or other errors
    console.error(`  Result: ❌ ERROR:`, err.message);
    return res.status(500).send('Server error');
  }
}

// Route for files: /auth/:groupName/:assetPath
app.get('/auth/:groupName/:assetPath', authenticateRequest);

// Route for directories: /auth/:groupName or /auth/:groupName/
app.get('/auth/:groupName', authenticateRequest);

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Start server (after initializing JWT secret)
const PORT = 3002;

async function startServer() {
  await initializeSecret();

  app.listen(PORT, () => {
    console.log('');
    console.log('==========================================');
    console.log('  Wiki.js Asset Authentication Service');
    console.log('==========================================');
    console.log(`  Listening on: http://localhost:${PORT}`);
    console.log(`  Database: wikijs@localhost:5432`);
    console.log(`  JWT Verification: ENABLED ✓`);
    console.log('');
    console.log('  Folder → Group Mapping:');
    console.log('    /secure-assets/managers/* → "managers" group');
    console.log('    /secure-assets/vacation/* → "vacation" group');
    console.log('    /secure-assets/{GROUP}/* → "{GROUP}" group');
    console.log('');
    console.log('  Press Ctrl+C to stop');
    console.log('==========================================');
    console.log('');
  });
}

startServer().catch(err => {
  console.error('Failed to start server:', err);
  process.exit(1);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\nShutting down...');
  pool.end(() => {
    console.log('Database pool closed');
    process.exit(0);
  });
});
