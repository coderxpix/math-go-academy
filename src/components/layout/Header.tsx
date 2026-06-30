import { Link, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { LogOut, User, LayoutDashboard, ChevronDown, Menu, Home, Info, BarChart2, HelpCircle, Book, Phone } from 'lucide-react';
import { Sheet, SheetContent, SheetTrigger } from '@/components/ui/sheet';
import { ThemeToggle } from '@/components/ThemeToggle';
import { useState } from 'react';
const logoImg = '/718d018f-b9e2-4bc3-8bc2-81520e0f0a7e.png';
import { cn } from '@/lib/utils';
export function Header() {
  const { user, profile, isAdmin, signOut } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);

  const handleSignOut = async () => {
    await signOut();
    navigate('/');
  };

  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map((n) => n[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  const navLinks = [
    { href: '/tests', label: 'Testlar' },
    { href: '/leaderboard', label: 'Reyting' },
    ...(user ? [{ href: '/dashboard', label: 'Dashboard' }] : []),
  ];

  const mobileNavLinks = [
    { href: '/', label: 'Home', icon: Home },
    ...(user ? [{ href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard }] : []),
    { href: '/leaderboard', label: 'Reyting', icon: BarChart2 },
    { href: '/tests', label: 'Tests', icon: HelpCircle },
    ...(user ? [{ href: '/profile', label: 'Profile', icon: User }] : []),
  ];

  return (
    <header className="sticky top-0 z-50 w-full bg-[#E6E1DC] dark:bg-[#00003C] border-b border-black/10 dark:border-white/10 transition-all duration-300">
      <div className="container flex h-16 md:h-20 items-center justify-between">
        {/* Logo */}
        <Link to="/" className="flex items-center gap-3 group">
          <img src={logoImg} alt="MATH GO Logo" className="h-9 w-9 md:h-11 md:w-11 rounded-md shadow-[0_0_15px_rgba(255,255,255,0.1)] transition-transform duration-300 group-hover:scale-105" />
          <div className="flex flex-col">
            <span className="font-serif text-lg md:text-xl font-bold tracking-tight text-[#00003C] dark:text-white">MATH GO</span>
          </div>
        </Link>

        {/* Desktop Nav */}
        <nav className="hidden md:flex items-center gap-1">
          {navLinks.map((link) => (
            <Link key={link.href} to={link.href}>
              <Button variant="ghost" size="sm" className="text-gray-700 dark:text-white/80 hover:text-[#00003C] dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors">
                {link.label}
              </Button>
            </Link>
          ))}
        </nav>

        {/* Right Side */}
        <div className="flex items-center gap-2">
          {/* ThemeToggle on Desktop only */}
          <div className="hidden md:block">
            <ThemeToggle />
          </div>

          {/* Mobile Menu */}
          <Sheet open={mobileOpen} onOpenChange={setMobileOpen}>
            <SheetTrigger asChild className="md:hidden">
              <Button variant="ghost" size="icon" className="text-[#00003C] dark:text-white hover:bg-black/5 dark:hover:bg-white/10">
                <Menu className="h-6 w-6" />
              </Button>
            </SheetTrigger>
            <SheetContent side="right" className="w-[85%] sm:w-80 p-0 flex flex-col bg-[#E6E1DC] dark:bg-[#00003C] border-l-0 shadow-2xl">
              {/* Sidebar Header */}
              <div className="bg-[#D9D3CE] dark:bg-black p-6 flex flex-col items-start gap-4 border-b border-black/10 dark:border-white/10 relative overflow-hidden">
                <div className="absolute top-0 right-0 w-32 h-32 bg-blue-500/10 rounded-full blur-3xl -z-10" />
                <div className="h-16 w-16 rounded-full shadow-[0_4px_20px_rgba(0,0,0,0.5)] bg-black flex items-center justify-center overflow-hidden border-2 border-[#1E1E1E]">
                  <img src={logoImg} alt="MATH GO Logo" className="h-full w-full object-cover" />
                </div>
                <div className="flex flex-col gap-0.5 z-10">
                  <span className="font-serif text-xl font-bold text-[#00003C] dark:text-white">MATH GO</span>
                  <span className="text-sm font-medium text-gray-700 dark:text-white/80">Math is easy with MATH GO</span>
                </div>
              </div>

              {/* Sidebar Links */}
              <nav className="flex-1 flex flex-col gap-1.5 p-4 overflow-y-auto">
                {mobileNavLinks.map((link) => {
                  const isActive = location.pathname === link.href;
                  return (
                    <Link
                      key={link.href}
                      to={link.href}
                      onClick={() => setMobileOpen(false)}
                      className={cn(
                        "flex items-center gap-4 px-4 py-3 rounded-xl transition-all duration-300 font-medium text-[15px] group relative overflow-hidden",
                        isActive
                          ? "text-[#00003C] dark:text-white bg-black/10 dark:bg-white/10"
                          : "text-gray-700 dark:text-white/80 hover:bg-black/5 dark:hover:bg-white/5 hover:text-[#00003C] dark:hover:text-white"
                      )}
                    >
                      {isActive && (
                        <div className="absolute left-0 top-1/2 -translate-y-1/2 w-1.5 h-8 bg-blue-500 rounded-r-full shadow-[0_0_10px_rgba(59,130,246,0.5)]" />
                      )}
                      <div className={cn(
                        "flex items-center justify-center p-2 rounded-lg transition-colors",
                        isActive ? "bg-black/20 dark:bg-white/20 shadow-sm" : "bg-transparent group-hover:bg-black/10 dark:group-hover:bg-white/10"
                      )}>
                        <link.icon className={cn("h-5 w-5", isActive ? "text-[#00003C] dark:text-white" : "text-gray-600 dark:text-white/70")} />
                      </div>
                      <span className="translate-y-[1px]">{link.label}</span>
                    </Link>
                  );
                })}

                <div className="my-3 border-t border-black/10 dark:border-white/10 mx-2"></div>

                {/* Theme Toggle inside Sidebar */}
                <div className="flex items-center justify-between px-4 py-3 bg-black/5 dark:bg-white/5 rounded-xl mx-2 shadow-sm backdrop-blur-sm">
                  <div className="flex items-center gap-3">
                    <div className="p-2 bg-black/10 dark:bg-white/10 rounded-lg">
                      <span className="text-xl leading-none block -translate-y-0.5">🌓</span>
                    </div>
                    <span className="text-[#00003C] dark:text-white font-semibold text-[14px]">Mavzu</span>
                  </div>
                  <ThemeToggle />
                </div>

                {!user && (
                  <div className="mt-6 flex flex-col gap-3 px-2">
                    <Link to="/login" onClick={() => setMobileOpen(false)}>
                      <Button variant="outline" className="w-full justify-start gap-3 border-black/20 dark:border-white/20 text-[#00003C] dark:text-white bg-transparent shadow-sm hover:bg-black/10 dark:hover:bg-white/10 hover:text-[#00003C] dark:hover:text-white h-12 rounded-xl font-semibold"><User className="h-5 w-5" />Kirish</Button>
                    </Link>
                  </div>
                )}

                {user && (
                  <div className="mt-6 px-2 mb-4">
                    <Button onClick={() => { handleSignOut(); setMobileOpen(false); }} variant="outline" className="w-full justify-start gap-3 text-[#ff6b6b] border-[#ff6b6b]/30 hover:bg-[#ff6b6b]/10 hover:border-[#ff6b6b] bg-transparent h-12 rounded-xl shadow-sm transition-all duration-300">
                      <LogOut className="h-5 w-5" />
                      <span className="font-semibold">Chiqish</span>
                    </Button>
                  </div>
                )}
              </nav>
            </SheetContent>
          </Sheet>

          {/* User Menu / Login on Desktop only */}
          <div className="hidden md:block">
            {user ? (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" className="flex items-center gap-2 h-auto p-2 hover:bg-black/5 dark:hover:bg-white/10 text-[#00003C] dark:text-white">
                    <Avatar className="h-9 w-9 border-2 border-black/20 dark:border-white/20 transition-transform duration-300 hover:scale-105">
                      <AvatarImage src={profile?.avatar_url || ''} />
                      <AvatarFallback className="bg-black/10 dark:bg-white/10 text-[#00003C] dark:text-white font-medium text-sm">
                        {profile?.full_name ? getInitials(profile.full_name) : 'U'}
                      </AvatarFallback>
                    </Avatar>
                    <span className="hidden sm:block text-sm font-medium">{profile?.full_name?.split(' ')[0]}</span>
                    <ChevronDown className="h-4 w-4 text-gray-700 dark:text-white/70" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent className="w-56 animate-fade-in" align="end">
                  <div className="flex items-center gap-3 p-3 border-b border-border/60">
                    <Avatar className="h-10 w-10 border-2 border-border">
                      <AvatarImage src={profile?.avatar_url || ''} />
                      <AvatarFallback className="bg-primary/10 text-primary font-medium">
                        {profile?.full_name ? getInitials(profile.full_name) : 'U'}
                      </AvatarFallback>
                    </Avatar>
                    <div className="flex flex-col">
                      <p className="text-sm font-medium">{profile?.full_name}</p>
                      <p className="text-xs text-muted-foreground">{user.email}</p>
                    </div>
                  </div>
                  <div className="p-1">
                    <DropdownMenuItem asChild>
                      <Link to="/profile" className="flex items-center gap-2 cursor-pointer">
                        <User className="h-4 w-4" />
                        Profil
                      </Link>
                    </DropdownMenuItem>
                  </div>
                  <DropdownMenuSeparator />
                  <div className="p-1">
                    <DropdownMenuItem onClick={handleSignOut} className="cursor-pointer text-destructive focus:text-destructive">
                      <LogOut className="h-4 w-4 mr-2" />
                      Chiqish
                    </DropdownMenuItem>
                  </div>
                </DropdownMenuContent>
              </DropdownMenu>
            ) : (
              <div className="flex items-center gap-3">
                <Link to="/login">
                  <Button variant="ghost" size="sm" className="text-[#00003C] dark:text-white hover:bg-black/5 dark:hover:bg-white/10">
                    Kirish
                  </Button>
                </Link>
              </div>
            )}
          </div>
        </div>
      </div>
    </header>
  );
}
