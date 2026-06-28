import { useReveal } from '../hooks/useReveal'
import styles from './Features.module.css'

const FEATURES = [
  {
    icon: '↗',
    title: 'Capture anything',
    description: 'Share a product link from Safari or any shopping app and it’s saved to your shelf in a tap.',
  },
  {
    icon: '✦',
    title: 'It fills itself in',
    description: 'Title, image, and price arrive on their own — your saved items look complete without any typing.',
  },
  {
    icon: '◑',
    title: 'File with a touch',
    description: 'Color-coded collections keep your finds in order. Long-press a card to file it away.',
  },
  {
    icon: '⟶',
    title: 'Buy when ready',
    description: 'One tap takes you back to the store — on your schedule, never on an algorithm’s.',
  },
  {
    icon: '⌂',
    title: 'Entirely yours',
    description: 'Everything stays on your device. No accounts, no servers, no noise watching over you.',
  },
  {
    icon: '⊘',
    title: 'Tidy archive',
    description: 'Mark things “Got it” or “Not anymore” to tuck them away — and restore them anytime.',
  },
]

export default function Features() {
  const ref = useReveal()

  return (
    <section id="features" className={styles.section} ref={ref}>
      <div className={styles.container}>
        <div className={`${styles.header} reveal`}>
          <p className={`${styles.eyebrow} eyebrow`}>Features</p>
          <h2 className={styles.title}>Quiet by design.</h2>
          <p className={styles.sub}>
            Everything you need to keep track of what you want — and nothing
            that nags you to buy it.
          </p>
        </div>

        <div className={styles.grid}>
          {FEATURES.map((feat, i) => (
            <div
              key={feat.title}
              className={`${styles.card} reveal`}
              style={{ transitionDelay: `${i * 70}ms` }}
            >
              <span className={styles.icon}>{feat.icon}</span>
              <h3 className={styles.cardTitle}>{feat.title}</h3>
              <p className={styles.cardDesc}>{feat.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
