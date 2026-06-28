import { useEffect, useRef } from 'react'
import { Link } from 'react-router-dom'
import styles from './Hero.module.css'

// Two staggered columns of saved-item cards — a calm preview of the shelf.
const COLUMNS = [
  [
    { title: 'Ceramic pour-over', price: '$48', tone: 'sand', dot: '#7E8C6A', h: 132 },
    { title: 'Walnut desk shelf', price: '$89', tone: 'clay', dot: '#C2663F', h: 96 },
    { title: 'Wool floor runner', price: '$210', tone: 'sage', dot: '#5E7C8B', h: 116 },
  ],
  [
    { title: 'Linen throw', price: '$120', tone: 'rose', dot: '#B0795F', h: 104 },
    { title: 'Olivewood board', price: '$34', tone: 'olive', dot: '#9A8C5A', h: 140 },
    { title: 'Brass table lamp', price: '$156', tone: 'amber', dot: '#C8923F', h: 92 },
  ],
]

export default function Hero() {
  const cardsRef = useRef([])

  useEffect(() => {
    cardsRef.current.forEach((card, i) => {
      if (card) {
        setTimeout(() => card.classList.add(styles.cardVisible), 350 + i * 130)
      }
    })
  }, [])

  let cardIndex = 0

  return (
    <section className={styles.hero}>
      <div className={styles.glow} aria-hidden="true" />

      <div className={styles.inner}>
        <div className={styles.content}>
          <p className={`${styles.eyebrow} eyebrow`}>Your calm product stash</p>
          <h1 className={styles.headline}>
            <span className={styles.line1}>Save it now.</span>
            <span className={styles.line2}>Buy it when you're ready.</span>
          </h1>
          <p className={styles.sub}>
            Silo is a quiet, private locker for the things you want to buy.
            Share a link from any app and it lands here — gently filled in with
            its image and price — ready for whenever you are.
          </p>
          <div className={styles.ctas}>
            <a href="#get" className={styles.ctaPrimary}>Get Silo</a>
            <Link to="/support" className={styles.ctaGhost}>How it works</Link>
          </div>
          <p className={styles.meta}>iPhone · No accounts · Everything on-device</p>
        </div>

        <div className={styles.shelf} aria-hidden="true">
          {COLUMNS.map((col, c) => (
            <div key={c} className={styles.column} data-col={c}>
              {col.map((item) => {
                const i = cardIndex++
                return (
                  <div
                    key={item.title}
                    ref={el => (cardsRef.current[i] = el)}
                    className={styles.card}
                    style={{ '--float-delay': `${i * 0.6}s` }}
                  >
                    <span
                      className={styles.collectionDot}
                      style={{ background: item.dot }}
                    />
                    <div
                      className={`${styles.thumb} ${styles[item.tone]}`}
                      style={{ height: `${item.h}px` }}
                    />
                    <div className={styles.cardBody}>
                      <span className={styles.cardTitle}>{item.title}</span>
                      <span className={styles.cardPrice}>{item.price}</span>
                    </div>
                  </div>
                )
              })}
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
