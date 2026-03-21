'use client'

import { InputHTMLAttributes, forwardRef } from 'react'

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  ({ className = '', ...props }, ref) => {
    return (
      <input
        ref={ref}
        className={`
          w-full px-3 py-2 rounded-lg border border-border bg-surface
          text-foreground text-sm placeholder:text-gray-light
          focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary
          transition-all duration-150
          ${className}
        `}
        {...props}
      />
    )
  }
)
Input.displayName = 'Input'
