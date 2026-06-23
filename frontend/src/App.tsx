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
        {/* Mobile: brand + profile on row 1, nav wraps to a full-width row 2.
            sm+: single row brand | nav | profile. */}
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3 sm:px-6">
          <div className="flex items-center gap-2 font-semibold">
            <Activity className="text-accent" size={20} />
            Lab Tracker
          </div>
          <div className="order-2 ml-auto sm:order-3">
            <ProfileSwitcher />
          </div>
          <nav className="order-3 flex w-full items-center justify-center gap-1 sm:order-2 sm:ml-2 sm:w-auto sm:justify-start">
            <NavItem to="/" icon={<LayoutGrid size={16} />} label="Dashboard" />
            <NavItem to="/upload" icon={<UploadIcon size={16} />} label="Upload" />
            <NavItem to="/reports" icon={<FileText size={16} />} label="Reports" />
          </nav>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
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
