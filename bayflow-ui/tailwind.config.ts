import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}", "./pages/**/*.{ts,tsx}", "./styles/**/*.{ts,tsx,css}"],
  theme: {
    extend: {
      colors: {
        brand: {
          50: "#f4f7ff",
          100: "#e1e7ff",
          500: "#2563eb",
          600: "#1d4ed8",
          700: "#1e3a8a"
        }
      }
    }
  },
  plugins: [],
};

export default config;
