// 인증 API 함수

import client from "./client";
import type { TokenResponse, UserInfo } from "@/shared/types";

export const authApi = {
  login: (username: string, password: string) =>
    client.post<TokenResponse>("/auth/login", { username, password }).then((r) => r.data),

  refresh: (refreshToken: string) =>
    client.post<TokenResponse>("/auth/refresh", null, { params: { refresh_token: refreshToken } }).then((r) => r.data),

  logout: (refreshToken: string) =>
    client.post("/auth/logout", null, { params: { refresh_token: refreshToken } }),

  me: () => client.get<UserInfo>("/auth/me").then((r) => r.data),
};
