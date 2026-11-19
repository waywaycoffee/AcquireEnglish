import { Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider, useAuth } from "./auth";
import HomePage from "./pages/HomePage";
import LandingPage from "./pages/LandingPage";
import LoginPage from "./pages/LoginPage";
import NetdiskPage from "./pages/NetdiskPage";
import PhoneLoginPage from "./pages/PhoneLoginPage";
import PrivacyPage from "./pages/PrivacyPage";
import RegisterPage from "./pages/RegisterPage";
import StudyPage from "./pages/StudyPage";
import TermsPage from "./pages/TermsPage";
import WechatMockLoginPage from "./pages/WechatMockLoginPage";

function Protected({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  if (loading) {
    return (
      <div className="auth-wrap">
        <div className="muted">加载中…</div>
      </div>
    );
  }
  if (!user) return <Navigate to="/login" replace />;
  return children;
}

export default function App() {
  return (
    <AuthProvider>
      <Routes>
        {/* Public product site for WeChat / store review — no login wall */}
        <Route path="/" element={<LandingPage />} />
        <Route path="/about" element={<LandingPage />} />
        <Route path="/privacy" element={<PrivacyPage />} />
        <Route path="/terms" element={<TermsPage />} />
        <Route path="/login" element={<LoginPage />} />
        <Route path="/login/phone" element={<PhoneLoginPage />} />
        <Route path="/login/wechat" element={<WechatMockLoginPage />} />
        <Route path="/register" element={<RegisterPage />} />
        <Route
          path="/app"
          element={
            <Protected>
              <HomePage />
            </Protected>
          }
        />
        <Route
          path="/app/netdisk"
          element={
            <Protected>
              <NetdiskPage />
            </Protected>
          }
        />
        <Route
          path="/courses/:courseId"
          element={
            <Protected>
              <StudyPage />
            </Protected>
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AuthProvider>
  );
}
