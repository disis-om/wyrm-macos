/* Included in the home mailbox translation unit; writes remain bounded and locked. */
void wyrm_mac_play(const char* nickname, const char* arena, bool offline) {
  if (!home_mutex || !nickname || !arena) return;
  SDL_LockMutex(home_mutex);
  snprintf(pending_nickname, sizeof(pending_nickname), "%s", nickname);
  snprintf(pending_enter_arena, sizeof(pending_enter_arena), "%s", arena);
  pending_ai_enter = offline;
  pending_enter = !offline;
  pending_enter_id = last_enter_id + 1;
  SDL_UnlockMutex(home_mutex);
}
void wyrm_mac_death(bool home) {
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_death_home = home;
  pending_death_play = !home;
  SDL_UnlockMutex(home_mutex);
}
