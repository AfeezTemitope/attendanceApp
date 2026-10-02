/** The fragment (#token=…) is never sent to any server, including our own. */
export const pairingLink = (token: string) => `${window.location.origin}/kiosk/pair#token=${encodeURIComponent(token)}`;
