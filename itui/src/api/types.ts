/**
 * Wire types that mirror `imsg serve`'s HTTP payloads. Kept intentionally loose (optional
 * fields) so the client survives server upgrades that add new properties without needing
 * a matching TUI release.
 */
export interface ResolvedContact {
  handle: string;
  name?: string;
  initials: string;
  has_avatar: boolean;
  avatar_mime?: string;
  avatar_path?: string;
  avatar_url?: string;
  avatar_base64?: string;
  avatar_bytes: number;
}

export interface ChatRow {
  id: number;
  name: string;
  identifier: string;
  guid: string;
  service: string;
  last_message_at: string;
  participants: string[];
  is_group: boolean;
  participants_resolved?: ResolvedContact[];
}

export interface Attachment {
  id: number;
  filename: string;
  transfer_name: string;
  uti: string;
  mime_type: string;
  total_bytes: number;
  is_sticker: boolean;
  original_path: string;
  missing: boolean;
  attachment_url?: string;
}

export interface Reaction {
  id: number;
  type: string;
  emoji: string;
  sender: string;
  is_from_me: boolean;
  created_at: string;
}

export interface Message {
  id: number;
  chat_id: number;
  guid: string;
  sender: string;
  is_from_me: boolean;
  text: string;
  created_at: string;
  attachments: Attachment[];
  reactions: Reaction[];
  destination_caller_id?: string;
  reply_to_guid?: string;
  thread_originator_guid?: string;
  // Reaction-event metadata (populated when the message IS a reaction row).
  is_reaction?: boolean;
  reaction_type?: string;
  reaction_emoji?: string;
  is_reaction_add?: boolean;
  reacted_to_guid?: string;
  sender_contact?: ResolvedContact;
}
