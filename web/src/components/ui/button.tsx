'use client'

import { ButtonHTMLAttributes, forwardRef } from 'react'

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger'
type Size = 'sm' | 'md' | 'lg'

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant
  size?: Size
}

const variantClasses: Record<Variant, string> = {
  primary: 'bg-primary text-white hover:bg-primary-dark shadow-sm',
  secondary: 'bg-surface border border-border text-foreground hover:bg-bg-secondary',
  ghost: 'text-foreground-secondary hover:bg-bg-secondary hover:text-foreground',
  danger: 'bg-red-600 text-white hover:bg-red-700 shadow-sm',
}

const sizeClasses: Record<Size, string> = {
  sm: 'px-2.5 py-1 text-[13px]',
  md: 'px-4 py-2 text-sm',
  lg: 'px-6 py-2.5 text-base',
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ variant = 'primary', size = 'md', className = '', children, ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={`
          inline-flex items-center justify-center gap-1.5 rounded-lg
          font-medium tracking-tight
          transition-all duration-150 cursor-pointer
          disabled:opacity-40 disabled:cursor-not-allowed disabled:shadow-none
          ${variantClasses[variant]} ${sizeClasses[size]} ${className}
        `}
        {...props}
      >
        {children}
      </button>
    )
  }
)
Button.displayName = 'Button'
