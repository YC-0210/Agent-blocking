import { readFileSync } from 'node:fs';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { createFocusMcp } from './mcp.mjs';

try {
  const relayURL = process.env.DO_CARD_RELAY_URL;
  const file = process.env.DO_CARD_AGENT_TOKEN_FILE;
  if (!relayURL || !file) throw new Error('Set DO_CARD_RELAY_URL and DO_CARD_AGENT_TOKEN_FILE');
  const agentToken = readFileSync(file, 'utf8').trim();
  if (agentToken.length < 32) throw new Error('Agent token must contain at least 32 characters');
  const server = createFocusMcp({ relayURL, agentToken, defaultDeviceId: process.env.DO_CARD_DEFAULT_DEVICE_ID });
  await server.connect(new StdioServerTransport());
} catch (error) {
  console.error(`DO Card MCP: ${error.message}`);
  process.exitCode = 1;
}
