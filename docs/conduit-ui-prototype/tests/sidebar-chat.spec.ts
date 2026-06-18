import { expect, test } from "@playwright/test"
import type { Page, TestInfo } from "@playwright/test"

async function openSidebar(page: Page) {
  const headerButton = page.locator("header").getByRole("button", { name: "Open sidebar" })
  if (await headerButton.isVisible()) {
    await headerButton.click()
  }
}

function artifactPreview(page: Page, testInfo: TestInfo) {
  return page.getByTestId(testInfo.project.name === "mobile" ? "artifact-preview-mobile" : "artifact-preview")
}

test.beforeEach(async ({ page }) => {
  await page.goto("/interactive")
})

test("renders all sidebar chat variants", async ({ page }) => {
  for (const variant of ["chat", "attention", "fleet"]) {
    await page.getByTestId(`variant-${variant}`).first().click()
    await expect(page.getByTestId(`variant-screen-${variant}`)).toBeVisible()
  }
})

test("search filters saved threads", async ({ page }) => {
  const search = page.getByTestId("thread-search")
  await search.fill("unified")
  await expect(page.getByTestId("thread-row-thread-diff")).toBeVisible()
  await expect(page.getByTestId("thread-row-thread-release")).toHaveCount(0)
})

test("new chat creates a selectable thread and follow-up appends a message", async ({ page }) => {
  await page.getByTestId("new-chat").click()
  await expect(page.getByTestId("active-thread-title")).toHaveText("New agent chat")

  await page.getByTestId("composer-input").fill("Add the sidebar screenshot checklist.")
  await page.getByTestId("send-follow-up").click()

  await expect(page.getByText("Add the sidebar screenshot checklist.").nth(1)).toBeVisible()
  await expect(page.getByText("Follow-up accepted.")).toBeVisible()
})

test("continue old thread preloads the composer", async ({ page }) => {
  await page.getByTestId("continue-thread-followup").click()
  await expect(page.getByTestId("active-thread-title")).toHaveText("Continue Claude session from phone")
  await expect(page.getByTestId("composer-input")).toHaveValue("Continue from the last result and explain the next step.")
})

test("approval decision resumes the related thread", async ({ page }) => {
  await page.getByTestId("variant-attention").first().click()
  await page.getByTestId("approve-att-approval").click()

  await expect(page.getByTestId("active-thread-title")).toHaveText("Ship sidebar chat prototype")
  await expect(page.getByText("Approve rewrite approved.")).toBeVisible()
})

test("fleet agent opens its related chat", async ({ page }) => {
  await page.getByTestId("variant-fleet").first().click()
  await page.getByTestId("fleet-agent-fleet-vps-claude").click()

  await expect(page.getByTestId("active-thread-title")).toHaveText("Continue Claude session from phone")
})

test("artifact buttons open preview states", async ({ page }, testInfo) => {
  await page.getByTestId("sidebar-toggle").click()
  await page.getByTestId("message-artifact-diff").first().click()
  await expect(artifactPreview(page, testInfo)).toContainText("app/interactive/page.tsx")

  await openSidebar(page)
  await page.getByTestId("thread-row-thread-followup").click()
  await page.getByTestId("message-artifact-files").first().click()
  await expect(artifactPreview(page, testInfo)).toContainText("lib/sidebar-chat-data.ts")

  await openSidebar(page)
  await page.getByTestId("thread-row-thread-release").click()
  await page.getByTestId("message-artifact-tests").first().click()
  await expect(artifactPreview(page, testInfo)).toContainText("lint")
})

test.describe("mobile drawer", () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test("opens and closes the sidebar drawer", async ({ page }) => {
    await expect(page.getByTestId("sidebar-panel")).toBeVisible()
    await page.getByTestId("sidebar-toggle").click()
    await expect(page.getByTestId("new-chat")).not.toBeInViewport()

    await page.locator("header").getByRole("button", { name: "Open sidebar" }).click()
    await expect(page.getByTestId("new-chat")).toBeInViewport()
  })
})
