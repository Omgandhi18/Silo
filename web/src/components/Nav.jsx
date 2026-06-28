import { Link, useLocation } from 'react-router-dom'
import styles from './Nav.module.css'

export default function Nav() {
  const { pathname } = useLocation()
  const isHome = pathname === '/'

  return (
    <nav className={styles.nav}>
      <div className={styles.inner}>
        <Link to="/" className={styles.logo}>
          <span className={styles.mark} aria-hidden="true">
            <span className={styles.markDot} />
          </span>
          Silo
        </Link>
        <div className={styles.links}>
          <Link to="/support" className={styles.navLink}>Support</Link>
          {isHome
            ? <a href="#get" className={styles.cta}>Get Silo</a>
            : <Link to="/#get" className={styles.cta}>Get Silo</Link>
          }
        </div>
      </div>
    </nav>
  )
}
