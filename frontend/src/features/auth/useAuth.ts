import { useNavigate } from "react-router-dom";
import { authApi } from "@/shared/api/auth";
import { useAuthStore } from "@/store/auth";
import { connectSocket, disconnectSocket } from "@/shared/socket";

export function useAuth() {
  const navigate = useNavigate();
  const { user, setAuth, clearAuth } = useAuthStore();

  const login = async (username: string, password: string) => {
    const tokens = await authApi.login(username, password);
    const me = await authApi.me();
    setAuth(me, tokens.access_token, tokens.refresh_token);
    connectSocket();
    navigate("/");
  };

  const logout = async () => {
    const rt = useAuthStore.getState().refreshToken;
    if (rt) await authApi.logout(rt).catch(() => {});
    clearAuth();
    disconnectSocket();
    navigate("/login");
  };

  return { user, login, logout, isAuthenticated: !!user };
}
