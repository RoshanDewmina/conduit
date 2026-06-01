'use client'

import { useState, useEffect, useRef, useCallback } from 'react'

// ─── Typewriter hook ──────────────────────────────────────────────────────────

function useTypewriter(text: string, speed = 38, startDelay = 600) {
  const [displayed, setDisplayed] = useState('')
  const [done, setDone] = useState(false)

  useEffect(() => {
    setDisplayed('')
    setDone(false)
    let i = 0
    let intervalId: ReturnType<typeof setInterval>

    const timeoutId = setTimeout(() => {
      intervalId = setInterval(() => {
        i++
        setDisplayed(text.slice(0, i))
        if (i >= text.length) {
          clearInterval(intervalId)
          setDone(true)
        }
      }, speed)
    }, startDelay)

    return () => {
      clearTimeout(timeoutId)
      clearInterval(intervalId)
    }
  }, [text, speed, startDelay])

  return { displayed, done }
}

// ─── Video background (mouse-scrub) ──────────────────────────────────────────

function VideoBackground() {
  const videoRef = useRef<HTMLVideoElement>(null)
  const prevXRef = useRef<number | null>(null)
  const targetTimeRef = useRef(0)
  const seekingRef = useRef(false)

  const seekTo = useCallback((time: number) => {
    const video = videoRef.current
    if (!video) return
    seekingRef.current = true
    video.currentTime = time
  }, [])

  useEffect(() => {
    const video = videoRef.current
    if (!video) return

    const handleSeeked = () => {
      seekingRef.current = false
      if (Math.abs(video.currentTime - targetTimeRef.current) > 0.05) {
        seekTo(targetTimeRef.current)
      }
    }

    const handleMouseMove = (e: MouseEvent) => {
      if (prevXRef.current === null) {
        prevXRef.current = e.clientX
        return
      }
      const delta = e.clientX - prevXRef.current
      prevXRef.current = e.clientX

      if (!video.duration) return

      const newTime = Math.max(
        0,
        Math.min(
          video.duration,
          video.currentTime + (delta / window.innerWidth) * 0.8 * video.duration
        )
      )
      targetTimeRef.current = newTime
      if (!seekingRef.current) seekTo(newTime)
    }

    video.addEventListener('seeked', handleSeeked)
    window.addEventListener('mousemove', handleMouseMove)
    return () => {
      video.removeEventListener('seeked', handleSeeked)
      window.removeEventListener('mousemove', handleMouseMove)
    }
  }, [seekTo])

  return (
    <video
      ref={videoRef}
      muted
      playsInline
      preload="auto"
      style={{
        position: 'fixed',
        inset: 0,
        width: '100%',
        height: '100%',
        objectFit: 'cover',
        objectPosition: '70% center',
        zIndex: 0,
      }}
    >
      <source
        src="https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260530_042513_df96a13b-6155-4f6e-8b93-c9dee66fba08.mp4"
        type="video/mp4"
      />
    </video>
  )
}

// ─── Navbar ───────────────────────────────────────────────────────────────────

const NAV_LINKS = ['Labs', 'Studio', 'Openings', 'Shop']

function Navbar() {
  const [menuOpen, setMenuOpen] = useState(false)

  return (
    <>
      <nav
        className="px-5 sm:px-8 py-4 sm:py-5 flex items-center justify-between"
        style={{ position: 'fixed', top: 0, left: 0, right: 0, zIndex: 10 }}
      >
        {/* Logo */}
        <div className="flex items-center gap-3">
          <span
            style={{
              fontWeight: 500,
              fontSize: 'clamp(18px, 3vw, 26px)',
              letterSpacing: '-0.02em',
              color: '#000',
            }}
          >
            Mainframe
            <sup style={{ fontSize: '0.55em', verticalAlign: 'super', letterSpacing: 0 }}>®</sup>
          </span>
          <span
            className="select-none"
            aria-hidden="true"
            style={{ fontSize: 'clamp(22px, 3vw, 30px)', letterSpacing: '-0.02em', color: '#000' }}
          >
            ✳︎
          </span>
        </div>

        {/* Desktop nav — comma-separated */}
        <div className="hidden md:flex items-center" style={{ fontSize: 23, color: '#000' }}>
          {NAV_LINKS.map((link, i) => (
            <span key={link}>
              <a href="#" className="hover:opacity-60 transition-opacity">
                {link}
              </a>
              {i < NAV_LINKS.length - 1 && (
                <span className="opacity-30 select-none">, </span>
              )}
            </span>
          ))}
        </div>

        {/* Desktop CTA */}
        <a
          href="#"
          className="hidden md:inline hover:opacity-60 transition-opacity"
          style={{
            fontSize: 23,
            color: '#000',
            textDecoration: 'underline',
            textUnderlineOffset: '2px',
          }}
        >
          Get in touch
        </a>

        {/* Mobile hamburger */}
        <button
          className="md:hidden flex flex-col p-1 cursor-pointer"
          style={{ gap: 5 }}
          onClick={() => setMenuOpen((v) => !v)}
          aria-label="Toggle navigation"
        >
          {([0, 1, 2] as const).map((i) => (
            <span
              key={i}
              className="block bg-black transition-all duration-300"
              style={{
                width: 24,
                height: 2,
                opacity: i === 1 ? (menuOpen ? 0 : 1) : 1,
                transform:
                  i === 0
                    ? menuOpen
                      ? 'translateY(7px) rotate(45deg)'
                      : 'none'
                    : i === 2
                    ? menuOpen
                      ? 'translateY(-7px) rotate(-45deg)'
                      : 'none'
                    : 'none',
              }}
            />
          ))}
        </button>
      </nav>

      {/* Mobile overlay */}
      <div
        className="md:hidden fixed inset-0 flex flex-col justify-center px-8 backdrop-blur-sm transition-all duration-300"
        style={{
          zIndex: 9,
          background: 'rgba(255,255,255,0.95)',
          gap: 32,
          opacity: menuOpen ? 1 : 0,
          pointerEvents: menuOpen ? 'auto' : 'none',
        }}
      >
        {NAV_LINKS.map((link) => (
          <a
            key={link}
            href="#"
            className="hover:opacity-60 transition-opacity"
            style={{ fontSize: 32, fontWeight: 500, color: '#000' }}
          >
            {link}
          </a>
        ))}
        <a
          href="#"
          style={{
            fontSize: 32,
            fontWeight: 500,
            color: '#000',
            textDecoration: 'underline',
            textUnderlineOffset: '2px',
          }}
        >
          Get in touch
        </a>
      </div>
    </>
  )
}

// ─── Copy icon ────────────────────────────────────────────────────────────────

function CopyIcon() {
  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 12 12"
      fill="none"
      aria-hidden="true"
      style={{ flexShrink: 0 }}
    >
      <rect
        x="4"
        y="4"
        width="7.5"
        height="7.5"
        rx="1.2"
        stroke="currentColor"
        strokeWidth="1.2"
      />
      <path
        d="M1 8V1.5A.5.5 0 0 1 1.5 1H8"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  )
}

// ─── Page ─────────────────────────────────────────────────────────────────────

const TYPEWRITER_TEXT =
  'Glad you stopped in. Good taste tends to find us. Now, what are we building?'

const WHITE_PILLS = [
  'Pitch us an idea',
  'Come work here',
  'Send a brief hello',
  'See how we operate',
]

export default function MainframePage() {
  const { displayed, done } = useTypewriter(TYPEWRITER_TEXT)

  const [pillsVisible, setPillsVisible] = useState(false)
  useEffect(() => {
    const t = setTimeout(() => setPillsVisible(true), 400)
    return () => clearTimeout(t)
  }, [])

  const copyEmail = () => {
    navigator.clipboard.writeText('hello@mainframe.co').catch(() => undefined)
  }

  return (
    <div className="min-h-screen bg-white">
      <VideoBackground />
      <Navbar />

      {/* Hero */}
      <section
        className="h-screen flex flex-col justify-end pb-12 md:justify-center md:pb-0 px-5 sm:px-8 md:px-10 overflow-hidden"
        style={{ position: 'relative', zIndex: 1 }}
      >
        <div className="max-w-xl" style={{ position: 'relative', zIndex: 10 }}>

          {/* Blurred intro label */}
          <div
            className="pointer-events-none select-none mb-5 sm:mb-6"
            style={{
              fontSize: 'clamp(18px, 4vw, 26px)',
              lineHeight: 1.3,
              fontWeight: 400,
              color: '#000',
              filter: 'blur(4px)',
            }}
          >
            <span>&#x203A; Hey there, meet A.R.I.A,</span>
            <br />
            <span>&#x203A; Mainframe&#x2019;s Adaptive Response Interface Agent</span>
          </div>

          {/* Typewriter paragraph */}
          <p
            className="mb-5 sm:mb-6"
            style={{
              fontSize: 'clamp(18px, 4vw, 26px)',
              lineHeight: 1.35,
              fontWeight: 400,
              color: '#000',
              minHeight: 54,
            }}
          >
            {displayed}
            {!done && (
              <span
                className="inline-block bg-black align-middle ml-[2px]"
                style={{
                  width: 2,
                  height: '1.1em',
                  animation: 'blink 1s step-end infinite',
                }}
              />
            )}
          </p>

          {/* Action pills */}
          <div
            className="flex flex-wrap gap-y-1"
            style={{
              opacity: pillsVisible ? 1 : 0,
              transform: pillsVisible ? 'translateY(0)' : 'translateY(8px)',
              transition: 'opacity 0.4s ease, transform 0.4s ease',
            }}
          >
            {WHITE_PILLS.map((label) => (
              <button
                key={label}
                className="
                  inline-flex items-center justify-center
                  bg-white text-black border border-black/10 rounded-full
                  text-[13px] sm:text-[15px]
                  px-4 sm:px-5 py-[0.3em]
                  mx-[0.2em] mb-[0.4em]
                  whitespace-nowrap
                  hover:bg-black hover:text-white
                  transition-colors duration-200
                  cursor-pointer
                "
              >
                {label}
              </button>
            ))}

            {/* Email / copy pill */}
            <button
              onClick={copyEmail}
              className="
                inline-flex items-center justify-center gap-2 sm:gap-3
                bg-transparent text-white border border-white rounded-full
                text-[13px] sm:text-[15px]
                px-4 sm:px-5 py-[0.3em]
                mx-[0.2em] mb-[0.4em]
                whitespace-nowrap
                hover:bg-white hover:text-black
                transition-colors duration-200
                cursor-pointer
              "
            >
              <span>
                Reach us:{' '}
                <span style={{ textDecoration: 'underline', textUnderlineOffset: 1 }}>
                  hello@mainframe.co
                </span>
              </span>
              <CopyIcon />
            </button>
          </div>
        </div>
      </section>
    </div>
  )
}
