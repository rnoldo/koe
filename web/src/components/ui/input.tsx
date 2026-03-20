'use client'

import { InputHTMLAttributes, forwardRef } from 'react'

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  ({ className = '', ...props }, ref) => {
    return (
      <input
        ref={ref}
        className={`
          w-full px-3 py-2 rounded-lg border border-gray bg-white font-serif
          text-foreground placeholder:text-gray
          focus:outline-none focus:ring-2 focus:ring-primary/40 focus:border-primary
          ${className}
        `}
        {...props}
      />
    )
  }
)
Input.displayName = 'Input'
