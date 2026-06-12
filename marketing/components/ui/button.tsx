import Link from "next/link";
import type { AnchorHTMLAttributes } from "react";

type Variant = "primary" | "ghost" | "light";

interface ButtonProps extends AnchorHTMLAttributes<HTMLAnchorElement> {
  href: string;
  variant?: Variant;
  mono?: boolean;
}

const variantClasses: Record<Variant, string> = {
  primary:
    "bg-accent text-white border border-accent hover:bg-accent/90 hover:border-accent/90",
  ghost:
    "bg-transparent text-fg border border-line hover:border-fg/40 hover:text-fg",
  light:
    "bg-white/90 text-[#0a0b0d] border border-white/90 hover:bg-white hover:border-white",
};

export default function Button({
  href,
  variant = "primary",
  mono = false,
  children,
  className = "",
  ...rest
}: ButtonProps) {
  const base =
    "inline-flex items-center justify-center gap-2 px-5 py-2.5 font-display font-semibold text-sm tracking-[.02em] lowercase transition-colors";
  const cls = `${base} ${variantClasses[variant]} ${mono ? "font-mono" : ""} ${className}`;

  const isExternal =
    href.startsWith("http") || href.startsWith("mailto") || rest.target === "_blank";

  if (isExternal) {
    return (
      <a href={href} className={cls} {...rest}>
        {children}
      </a>
    );
  }

  return (
    <Link href={href} className={cls} {...rest}>
      {children}
    </Link>
  );
}
