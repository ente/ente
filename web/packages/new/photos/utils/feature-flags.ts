/**
 * Shared rollout switch for the Photos V2 UI.
 *
 * Keep this in one module so the app and shared Photos components cannot end
 * up rendering a mixed V1/V2 flow.
 */
export const enableV2 = true as boolean;
