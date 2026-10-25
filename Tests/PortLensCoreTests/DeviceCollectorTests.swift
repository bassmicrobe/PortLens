import XCTest
import PortLensValidation

/// Full-Xcode adapter: all fixture/assertion logic lives in PortLensValidation.
final class DeviceCollectorTests: XCTestCase {
    func testPreservesNestedLogicalHubsAndDuplicateDeviceNames() throws {
        try CoreValidation.testPreservesNestedLogicalHubsAndDuplicateDeviceNames()
    }

    func testKeepsEmptyBusesWithoutTreatingThemAsPhysicalFreePorts() throws {
        try CoreValidation.testKeepsEmptyBusesWithoutTreatingThemAsPhysicalFreePorts()
    }

    func testThunderboltHierarchyUsesRoutesAndUpstreamLinkSpeed() throws {
        try CoreValidation.testThunderboltHierarchyUsesRoutesAndUpstreamLinkSpeed()
    }

    func testIdentifiersIgnoreConnectionGenerationAndSiblingOrdering() throws {
        try CoreValidation.testIdentifiersIgnoreConnectionGenerationAndSiblingOrdering()
    }

    func testIdentifierChangesWhenDifferentProductUsesSamePort() throws {
        try CoreValidation.testIdentifierChangesWhenDifferentProductUsesSamePort()
    }

    func testExportExcludesSensitiveAndUnknownSourceFields() throws {
        try CoreValidation.testExportExcludesSensitiveAndUnknownSourceFields()
    }

    func testMissingTransportProducesWarningAndInvalidSchemaThrows() throws {
        try CoreValidation.testMissingTransportProducesWarningAndInvalidSchemaThrows()
    }

    func testCapturesTimestampAndSyntheticDemoHasUniqueIdentifiers() throws {
        try CoreValidation.testCapturesTimestampAndSyntheticDemoHasUniqueIdentifiers()
    }

    func testDiagramSeparatesTransportSections() throws {
        try GraphValidation.testDiagramSeparatesTransportSections()
    }

    func testDiagramCollapsingRemovesHiddenDescendants() throws {
        try GraphValidation.testDiagramCollapsingRemovesHiddenDescendants()
    }

    func testDiagramRoutesOutsideCardsAndWithinBounds() throws {
        try GraphValidation.testDiagramRoutesOutsideCardsAndWithinBounds()
    }

    func testDiagramUsesOneSharedTrunkPerParent() throws {
        try GraphValidation.testDiagramUsesOneSharedTrunkPerParent()
    }

    func testDiagramHandlesEmptyAndFilteredTrees() throws {
        try GraphValidation.testDiagramHandlesEmptyAndFilteredTrees()
    }

    func testZoomFitsBothViewportDimensions() throws {
        try ZoomValidation.testZoomFitsBothViewportDimensions()
    }

    func testZoomFitsCrowdedDiagramBelowOldMinimum() throws {
        try ZoomValidation.testZoomFitsCrowdedDiagramBelowOldMinimum()
    }

    func testSideBySideOverviewImprovesFittedReadability() throws {
        try ZoomValidation.testSideBySideOverviewImprovesFittedReadability()
    }

    func testZoomHandlesSmallAndInvalidGeometry() throws {
        try ZoomValidation.testZoomHandlesSmallAndInvalidGeometry()
    }

    func testZoomManualStepsStayMonotonicAfterAutoFit() throws {
        try ZoomValidation.testZoomManualStepsStayMonotonicAfterAutoFit()
    }
}
