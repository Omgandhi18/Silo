import { useEffect, useRef } from 'react'

/**
 * Reveals any descendant carrying the `reveal` class as it scrolls into view
 * by toggling the global `visible` class (see App.css). One observer per
 * section keeps the markup declarative — components just tag elements.
 */
export function useReveal(threshold = 0.12) {
  const containerRef = useRef(null)

  useEffect(() => {
    const root = containerRef.current
    if (!root) return

    const targets = root.querySelectorAll('.reveal')
    if (!targets.length) return

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('visible')
            observer.unobserve(entry.target)
          }
        })
      },
      { threshold }
    )

    targets.forEach((el) => observer.observe(el))
    return () => observer.disconnect()
  }, [threshold])

  return containerRef
}
