import type { VariantProps } from "class-variance-authority"
import { cva } from "class-variance-authority"

export { default as Button } from "./Button.vue"

export const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-all disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4 shrink-0 [&_svg]:shrink-0 outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-3 aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive",
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground hover:bg-brand-600",
        destructive:
          "bg-destructive text-white hover:bg-destructive/90 focus-visible:ring-destructive/20 dark:focus-visible:ring-destructive/40 dark:bg-destructive/60",
        outline:
          "border bg-background shadow-xs hover:bg-accent hover:text-accent-foreground dark:bg-input/30 dark:border-input dark:hover:bg-input/50",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        ghost:
          "hover:bg-accent hover:text-accent-foreground dark:hover:bg-accent/50",
        link: "text-primary-text underline-offset-4 hover:underline",
        soft:
          "bg-primary-soft text-primary-text border border-brand-200 hover:bg-brand-100 dark:border-brand-500/30 dark:bg-brand-500/10 dark:hover:bg-brand-500/20",
        "ghost-destructive":
          "text-destructive hover:bg-destructive/10",
      },
      size: {
        "default": "h-9 px-4 py-2 has-[>svg]:px-3",
        "xs": "h-6 gap-1 rounded-md px-2 text-xs has-[>svg]:px-1.5 [&_svg:not([class*='size-'])]:size-3",
        "sm": "h-9 rounded-md gap-1.5 px-3 has-[>svg]:px-2.5",
        "lg": "h-10 rounded-md px-6 has-[>svg]:px-4",
        "icon": "size-9",
        "icon-xs": "size-6 rounded-md [&_svg:not([class*='size-'])]:size-3",
        "icon-sm": "size-8",
        "icon-lg": "size-10",
      },
    },
    compoundVariants: [
      { variant: "ghost", size: ["icon", "icon-sm", "icon-xs"], class: "bg-card text-muted-foreground hover:text-foreground border shadow-xs hover:bg-secondary" },
      { variant: "ghost-destructive", size: ["icon", "icon-sm", "icon-xs"], class: "border border-rose-200 bg-rose-50 shadow-xs hover:bg-rose-100 dark:border-rose-500/30 dark:bg-rose-500/10 dark:hover:bg-rose-500/20" },
      { variant: "soft", size: ["icon", "icon-sm", "icon-xs"], class: "shadow-xs" },
    ],
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
)
export type ButtonVariants = VariantProps<typeof buttonVariants>
