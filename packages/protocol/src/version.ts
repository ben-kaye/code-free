/** Wire protocol version negotiated on hello. Bump only on breaking changes. */
export const PROTOCOL_VERSION = 1 as const;

export type ProtocolVersion = typeof PROTOCOL_VERSION;
