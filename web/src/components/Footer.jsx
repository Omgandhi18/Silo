import { Link } from 'react-router-dom'
import styles from './Footer.module.css'

export default function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={styles.inner}>
        <div className={styles.left}>
          <Link to="/" className={styles.logo}>
            <span className={styles.mark} aria-hidden="true">
              <span className={styles.markDot} />
            </span>
            Silo
          </Link>
          <span className={styles.copy}>© 2026 Om Gandhi</span>
        </div>
        <div className={styles.links}>
          <Link to="/support" className={styles.link}>Support</Link>
          <Link to="/privacy" className={styles.link}>Privacy</Link>
          <a href="mailto:devilgandhi@gmail.com" className={styles.link}>Contact</a>
        </div>
      </div>
    </footer>
  )
}
