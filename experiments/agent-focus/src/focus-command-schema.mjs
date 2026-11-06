import { z } from 'zod';

// Shared delivery envelope; transport, APNs and queue behaviour remain in relay.mjs.
export const commandSchema = z.object({
  id: z.string().min(1).max(80), action: z.enum(['start', 'stop', 'set_maximum']),
  modeID: z.string().min(1).max(80), sessionID: z.string().min(1).max(80).optional(),
  durationMinutes: z.number().int().min(2).max(1440).optional(),
  renewalConfirmed: z.boolean().optional(),
  maximumMinutes: z.number().int().min(15).max(1440).optional(),
  expectedMaximumMinutes: z.number().int().min(15).max(1440).optional(),
  userConfirmed: z.literal(true).optional(),
  appGroupID: z.string().regex(/^[a-zA-Z0-9-]{1,80}$/).optional(),
}).strict().superRefine((command, context) => {
  const maximum = command.action === 'set_maximum';
  const valid = maximum
    ? command.maximumMinutes !== undefined && command.expectedMaximumMinutes !== undefined &&
      command.userConfirmed === true && command.sessionID === undefined &&
      command.durationMinutes === undefined && command.renewalConfirmed === undefined && command.appGroupID === undefined
    : command.sessionID !== undefined && (command.action !== 'start' || command.durationMinutes !== undefined) &&
      command.maximumMinutes === undefined &&
      command.expectedMaximumMinutes === undefined && command.userConfirmed === undefined &&
      (command.action === 'start' || command.appGroupID === undefined);
  if (!valid) context.addIssue({ code: 'custom', message: 'Session and maximum changes must be separate' });
});
