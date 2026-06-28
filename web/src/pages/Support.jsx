import { useEffect } from 'react'
import styles from './InnerPage.module.css'

export default function Support() {
  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  return (
    <div className={styles.page}>
      <div className={styles.hero}>
        <div className={styles.heroGlow} aria-hidden="true" />
        <div className={styles.heroInner}>
          <span className={`${styles.eyebrow} eyebrow`}>Support</span>
          <h1 className={styles.title}>How can we help?</h1>
          <p className={styles.subtitle}>
            Silo is a quiet place to keep the things you want to buy — share a
            link and it lands here, ready for whenever you are. Most questions
            are answered below; if not, an email is all it takes.
          </p>
        </div>
      </div>

      <div className={styles.body}>
        <h2>Getting started</h2>
        <ul>
          <li><strong>Save from anywhere.</strong> In Safari or a shopping app, tap the Share button and choose Silo. The link lands on your shelf and fills in its title, image, and price automatically.</li>
          <li><strong>Add by hand.</strong> Tap + in the top corner to paste a link, or enter a product’s details yourself.</li>
          <li><strong>Organize.</strong> Long-press a card to file it into a color-coded collection. Tap a card to open it, jot a note, or hit Open &amp; Buy to head back to the store.</li>
          <li><strong>Tidy up.</strong> Mark things “Got it” or “Not anymore” to move them into the Archive — and restore them anytime.</li>
        </ul>

        <h2>Frequently asked</h2>

        <p><strong>Silo isn’t in my Share sheet.</strong></p>
        <p>
          Open the Share sheet, scroll the app row to the end, tap More, and
          switch Silo on (you can drag it up to the front). You may need to open
          Silo once first.
        </p>

        <p><strong>My link didn’t fill in its details.</strong></p>
        <p>
          Some websites block automated reading. Open the item, tap Edit, and add
          the title, price, or image yourself — your edits are kept and never
          overwritten.
        </p>

        <p><strong>Where is my data stored?</strong></p>
        <p>
          Entirely on your device. Silo has no account and no cloud — see our{' '}
          <a href="/privacy">Privacy Policy</a>.
        </p>

        <p><strong>How do I change the default currency?</strong></p>
        <p>
          Open Settings (the gear icon) and pick your Default currency.
        </p>

        <h2>Still need help?</h2>
        <div className={styles.contactCard}>
          <strong>Get in touch</strong>
          <p>
            Email{' '}
            <a href="mailto:devilgandhi@gmail.com?subject=Silo%20Support">
              devilgandhi@gmail.com
            </a>{' '}
            and I’ll get back to you.
          </p>
        </div>

        <p className={styles.meta}>Last updated: June 2026</p>
      </div>
    </div>
  )
}
