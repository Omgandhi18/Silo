import { useReveal } from '../hooks/useReveal'
import styles from './HowItWorks.module.css'

const STEPS = [
  {
    number: '01',
    icon: '↗',
    title: 'Share a link',
    description: 'In Safari or a shopping app, tap Share and choose Silo. The item lands on your shelf instantly.',
  },
  {
    number: '02',
    icon: '✦',
    title: 'It fills itself in',
    description: 'Silo quietly reads the page for its title, image, and price — so your find looks complete on its own.',
  },
  {
    number: '03',
    icon: '⟶',
    title: 'Buy when you’re ready',
    description: 'File it into a collection, jot a note, and tap Open & Buy whenever the moment is right.',
  },
]

export default function HowItWorks() {
  const ref = useReveal(0.15)

  return (
    <section className={styles.section} ref={ref}>
      <div className={styles.container}>
        <div className={`${styles.header} reveal`}>
          <p className={`${styles.eyebrow} eyebrow`}>How it works</p>
          <h2 className={styles.title}>Three calm steps.</h2>
        </div>

        <div className={styles.grid}>
          {STEPS.map((step, i) => (
            <div
              key={step.number}
              className={`${styles.step} reveal`}
              style={{ transitionDelay: `${i * 110}ms` }}
            >
              <div className={styles.number}>{step.number}</div>
              <div className={styles.iconWrap}>
                <span className={styles.icon}>{step.icon}</span>
              </div>
              <h3 className={styles.stepTitle}>{step.title}</h3>
              <p className={styles.stepDesc}>{step.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
