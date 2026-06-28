import { useReveal } from '../hooks/useReveal'
import styles from './GetSilo.module.css'

// TODO: replace href with the real App Store URL once the listing is live,
// and set `available` to true to swap the badge from "Coming soon".
const APP_STORE_URL = '#'
const available = false

export default function GetSilo() {
  const ref = useReveal()

  return (
    <section id="get" className={styles.section} ref={ref}>
      <div className={styles.glow} aria-hidden="true" />
      <div className={styles.container}>
        <div className={`${styles.card} reveal`}>
          <div className={styles.mark} aria-hidden="true">
            <span className={styles.markInner}>
              <span className={styles.markDot} />
            </span>
          </div>
          <p className={`${styles.eyebrow} eyebrow`}>Get Silo</p>
          <h2 className={styles.title}>Your quiet shelf, on your iPhone.</h2>
          <p className={styles.sub}>
            Free to start. No account to create. Everything you save stays on your device.
          </p>

          <a
            href={APP_STORE_URL}
            className={styles.storeBtn}
            {...(APP_STORE_URL !== '#'
              ? { target: '_blank', rel: 'noopener noreferrer' }
              : { 'aria-disabled': 'true' })}
          >
            <svg className={styles.storeGlyph} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M17.05 12.54c-.02-2.06 1.68-3.05 1.76-3.1-.96-1.4-2.45-1.6-2.98-1.62-1.27-.13-2.48.75-3.12.75-.64 0-1.64-.73-2.7-.71-1.39.02-2.67.81-3.38 2.05-1.44 2.5-.37 6.2 1.04 8.23.69.99 1.51 2.1 2.58 2.06 1.04-.04 1.43-.67 2.69-.67 1.25 0 1.61.67 2.7.65 1.12-.02 1.82-1.01 2.5-2.01.79-1.15 1.11-2.27 1.13-2.33-.02-.01-2.17-.83-2.19-3.3zM15.1 6.18c.56-.69.94-1.64.84-2.59-.81.03-1.79.54-2.37 1.22-.52.6-.98 1.57-.86 2.49.9.07 1.83-.46 2.39-1.12z"/>
            </svg>
            <span className={styles.storeText}>
              <small>Download on the</small>
              App Store
            </span>
          </a>

          <div className={`${styles.badge} ${available ? '' : styles.badgeSoon}`}>
            <span className={styles.badgeDot} />
            {available ? 'Available now · iOS 17+' : 'Coming soon to the App Store'}
          </div>
        </div>
      </div>
    </section>
  )
}
