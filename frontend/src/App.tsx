import { NavLink, Route, Routes } from "react-router-dom";
import { clsx } from "clsx";
import { Activity, LayoutGrid, Upload as UploadIcon, FileText } from "lucide-react";
import { ProfileSwitcher } from "@/components/ProfileSwitcher";
import { Dashboard } from "@/pages/Dashboard";
import { AnalyteDetail } from "@/pages/AnalyteDetail";
import { Upload } from "@/pages/Upload";
import { Reports } from "@/pages/Reports";

function NavItem({
  to,
  icon,
  label,
}: {
  to: string;
  icon: React.ReactNode;
  label: string;
}) {
  return (
    <NavLink
      to={to}
      end={to === "/"}
      className={({ isActive }) =>
        clsx(
          "flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition",
          isActive ? "bg-accent/15 text-accent" : "text-muted hover:bg-panel2",
        )
      }
    >
      {icon}
      {label}
    </NavLink>
  );
}

export default function App() {
  return (
    <div className="min-h-full">
      <header className="sticky top-0 z-10 border-b border-border bg-bg/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-3">
          <div className="flex items-center gap-2 font-semibold">
            <Activity className="text-accent" size={20} />
            Lab Tracker
          </div>
          <nav className="flex items-center gap-1">
            <NavItem to="/" icon={<LayoutGrid size={16} />} label="Dashboard" />
            <NavItem to="/upload" icon={<UploadIcon size={16} />} label="Upload" />
            <NavItem to="/reports" icon={<FileText size={16} />} label="Reports" />
          </nav>
          <ProfileSwitcher />
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-6 py-6">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/analytes/:analyteId" element={<AnalyteDetail />} />
          <Route path="/upload" element={<Upload />} />
          <Route path="/reports" element={<Reports />} />
        </Routes>
      </main>
    </div>
  );
}
