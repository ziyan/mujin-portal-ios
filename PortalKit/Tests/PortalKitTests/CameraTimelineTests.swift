import Foundation
import Testing

@testable import PortalKit

private let hour = CameraTimeline.hourMS
private let minute = CameraTimeline.minuteMS

@Suite struct CameraTimelineTests {
    @Test func theTickStepFollowsTheVisibleSpan() {
        #expect(CameraTimeline.tickStepMS(forSpanMS: 24 * hour) == 3 * hour)
        #expect(CameraTimeline.tickStepMS(forSpanMS: 4 * hour) == hour)
        #expect(CameraTimeline.tickStepMS(forSpanMS: hour) == 15 * minute)
        #expect(CameraTimeline.tickStepMS(forSpanMS: 15 * minute) == 5 * minute)
        #expect(CameraTimeline.tickStepMS(forSpanMS: 2 * minute) == minute)
        #expect(CameraTimeline.tickStepMS(forSpanMS: 30_000) == 10_000)
        #expect(CameraTimeline.tickStepMS(forSpanMS: 10_000) == 5_000)
    }

    @Test func ticksFallOnWholeStepsInsideTheWindow() {
        let window = CameraTimeWindow(startMS: 7 * minute, endMS: 7 * minute + hour)
        let ticks = CameraTimeline.ticks(in: window)
        #expect(ticks.first == 15 * minute)
        #expect(ticks.last == 60 * minute)
        #expect(ticks.allSatisfy { $0.truncatingRemainder(dividingBy: 15 * minute) == 0 && $0 >= window.startMS && $0 <= window.endMS })
    }

    @Test func aWindowNeverReachesFartherThanNowPlusItsMargin() {
        let now = 1_000 * hour
        let window = CameraTimeWindow(startMS: now - hour, endMS: now + 0.5 * hour)
        let clamped = CameraTimeline.panned(window, byMS: 0, nowMS: now)
        #expect(clamped.spanMS == window.spanMS)
        #expect(clamped.endMS == now + CameraTimeline.nowMarginMS(spanMS: hour * 1.5))
    }

    @Test func panningBackIsNotLimited() {
        let now = 1_000 * hour
        let window = CameraTimeWindow(startMS: now - hour, endMS: now)
        let moved = CameraTimeline.panned(window, byMS: -10 * hour, nowMS: now)
        #expect(moved.startMS == now - 11 * hour)
        #expect(moved.spanMS == hour)
    }

    @Test func zoomKeepsTheAnchorWhereItWas() {
        let now = 1_000 * hour
        let window = CameraTimeWindow(startMS: 100 * hour, endMS: 104 * hour)
        let anchor = 101 * hour
        let zoomed = CameraTimeline.zoomed(window, factor: 0.25, anchorMS: anchor, nowMS: now)
        #expect(zoomed.spanMS == hour)
        #expect(abs(CameraTimeline.fraction(forTimeMS: anchor, in: zoomed) - 0.25) < 1e-9)
    }

    @Test func theSpanStaysBetweenTenSecondsAndADay() {
        let now = 1_000 * hour
        let window = CameraTimeWindow(startMS: 100 * hour, endMS: 101 * hour)
        #expect(CameraTimeline.resized(window, spanMS: 1, anchorMS: 100 * hour, nowMS: now).spanMS == 10_000)
        #expect(CameraTimeline.resized(window, spanMS: 100 * hour, anchorMS: 100 * hour, nowMS: now).spanMS == 24 * hour)
    }

    @Test func aMomentInTheFutureLandsOnNow() {
        let now = 1_000 * hour
        let view = CameraTimeline.viewForMoment(timeMS: now + 5 * hour, nowMS: now)
        #expect(view.playheadMS == now)
        #expect(view.window.spanMS == hour)
        #expect(view.window.endMS <= now + CameraTimeline.nowMarginMS(spanMS: hour) + 0.001)
    }

    @Test func aPastMomentIsCenteredInAnHour() {
        let now = 1_000 * hour
        let view = CameraTimeline.viewForMoment(timeMS: 500 * hour, nowMS: now)
        #expect(view.playheadMS == 500 * hour)
        #expect(view.window == CameraTimeWindow(startMS: 500 * hour - 0.5 * hour, endMS: 500 * hour + 0.5 * hour))
    }

    @Test func timestampsComeInAsNumbersStringsOrDates() {
        #expect(CameraTimeline.parseTimestamp("1700000000000") == 1_700_000_000_000)
        #expect(CameraTimeline.parseTimestamp(" 1700000000000.5 ") == 1_700_000_000_000.5)
        #expect(CameraTimeline.parseTimestamp("2023-11-14T22:13:20Z") == 1_700_000_000_000)
        #expect(CameraTimeline.parseTimestamp("") == nil)
        #expect(CameraTimeline.parseTimestamp("   ") == nil)
        #expect(CameraTimeline.parseTimestamp("yesterday") == nil)
    }

    @Test func aClipStartsTenSecondsBeforeThePlayhead() {
        let clip = CameraClip(aroundMS: 1_000_000, lengthMS: 60_000, nowMS: 5_000_000)
        #expect(clip.startMS == 990_000)
        #expect(clip.endMS == 1_050_000)
        #expect(clip.durationMS == 60_000)
    }

    @Test func aClipNearNowKeepsItsLengthByStartingEarlier() {
        let clip = CameraClip(aroundMS: 1_000_000, lengthMS: 60_000, nowMS: 1_020_000)
        #expect(clip.endMS == 1_020_000)
        #expect(clip.durationMS == 60_000)
        #expect(clip.startMS == 960_000)
    }

    @Test func aClipIsNeverLongerThanTheExportAllows() {
        let clip = CameraClip(aroundMS: 10_000_000, lengthMS: 3 * hour, nowMS: 99_000_000)
        #expect(clip.durationMS == 30 * minute)
    }
}

@Suite struct CameraClockTests {
    @Test func aKnownZoneIsTheControllersAndTheDayIsItsOwn() throws {
        let clock = CameraClock(identifier: "Asia/Tokyo")
        #expect(clock.isControllerZone)
        // 2023-11-14 22:13:20 UTC is 07:13:20 the next day in Tokyo, whatever zone the phone is in.
        let moment = 1_700_000_000_000.0
        #expect(clock.secondsSinceMidnight(atMS: moment) == 7 * 3600 + 13 * 60 + 20)
        #expect(clock.offsetSeconds(atMS: moment) == 9 * 3600)
    }

    @Test func anUnknownOrMissingZoneFallsBackToThePhonesAndSaysSo() {
        #expect(!CameraClock(identifier: nil).isControllerZone)
        #expect(!CameraClock(identifier: "").isControllerZone)
        #expect(!CameraClock(identifier: "Not/AZone").isControllerZone)
    }

    @Test func aDayJumpLandsOnTheControllersMidnight() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let moment = 1_700_000_000_000.0
        let dayStart = CameraDayJump.dayStartMS(containing: moment, in: tokyo)
        // Midnight in Tokyo of the 15th is 15:00 UTC of the 14th.
        #expect(dayStart == 1_699_974_000_000)
        let afternoon = CameraDayJump.target(dayStartMS: dayStart, block: CameraDayJump.afternoon, in: tokyo, nowMS: moment + 10 * hour)
        #expect(afternoon == dayStart + 12 * hour)
        let future = CameraDayJump.target(dayStartMS: dayStart, block: CameraDayJump.evening, in: tokyo, nowMS: dayStart + hour)
        #expect(future == dayStart + hour)
    }

    @Test func aDayWithAClockChangeKeepsTheWallClockHour() throws {
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        // 2023-11-05 is the day the clocks went back in Chicago, so it has 25 hours.
        let moment = 1_699_200_000_000.0
        let dayStart = CameraDayJump.dayStartMS(containing: moment, in: chicago)
        let noon = CameraDayJump.moment(dayStartMS: dayStart, hour: 12, in: chicago)
        #expect(noon - dayStart == 13 * hour)
    }
}
