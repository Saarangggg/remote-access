const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const envPath = path.join(__dirname, '.env');
const examplePath = path.join(__dirname, '.env.example');

// Helper to generate a secure random string
function generateSecureSecret() {
  return crypto.randomBytes(32).toString('hex');
}

function run() {
  console.log('--- RemoteConnect JWT Secret Generator ---');

  let envContent = '';

  // 1. Initialize .env from .env.example if it doesn't exist
  if (!fs.existsSync(envPath)) {
    if (!fs.existsSync(examplePath)) {
      console.error('Error: .env.example not found in ' + __dirname);
      process.exit(1);
    }
    console.log('No .env found. Creating .env from .env.example...');
    fs.copyFileSync(examplePath, envPath);
  }

  // 2. Read current .env
  envContent = fs.readFileSync(envPath, 'utf8');

  // 3. Generate secrets
  const accessSecret = generateSecureSecret();
  const refreshSecret = generateSecureSecret();

  // 4. Replace placeholder secrets or update existing keys
  let updatedContent = envContent;

  const accessSecretRegex = /^JWT_ACCESS_SECRET=.*$/m;
  const refreshSecretRegex = /^JWT_REFRESH_SECRET=.*$/m;

  if (accessSecretRegex.test(updatedContent)) {
    updatedContent = updatedContent.replace(accessSecretRegex, `JWT_ACCESS_SECRET=${accessSecret}`);
  } else {
    updatedContent += `\nJWT_ACCESS_SECRET=${accessSecret}`;
  }

  if (refreshSecretRegex.test(updatedContent)) {
    updatedContent = updatedContent.replace(refreshSecretRegex, `JWT_REFRESH_SECRET=${refreshSecret}`);
  } else {
    updatedContent += `\nJWT_REFRESH_SECRET=${refreshSecret}`;
  }

  // Write back to .env
  fs.writeFileSync(envPath, updatedContent, 'utf8');

  console.log('\nSuccess! Strong JWT secrets have been generated and updated in your .env file:');
  console.log(`- JWT_ACCESS_SECRET = ${accessSecret.slice(0, 8)}... (truncated)`);
  console.log(`- JWT_REFRESH_SECRET = ${refreshSecret.slice(0, 8)}... (truncated)`);
  console.log('\nPlease make sure to configure AGENT_USER and AGENT_PASSWORD in your .env file before running!');
}

run();
