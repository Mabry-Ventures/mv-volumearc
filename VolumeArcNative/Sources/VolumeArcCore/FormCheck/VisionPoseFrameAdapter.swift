#if canImport(Vision) && !os(watchOS)
import Foundation
import Vision

public enum VisionPoseFrameAdapter {
    public static func frame(
        from observation: VNHumanBodyPoseObservation,
        timestamp: TimeInterval,
        minimumConfidence: Double = 0.20
    ) -> FormCheckFrame? {
        var joints: [FormCheckJointName: FormCheckPoint] = [:]
        for mapping in jointMappings {
            guard let point = try? observation.recognizedPoint(mapping.visionJoint),
                  Double(point.confidence) >= minimumConfidence else {
                continue
            }
            joints[mapping.formCheckJoint] = FormCheckPoint(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
        guard !joints.isEmpty else { return nil }
        return FormCheckFrame(timestamp: timestamp, joints: joints)
    }

    private static let jointMappings: [JointMapping] = [
        JointMapping(.nose, .nose),
        JointMapping(.neck, .neck),
        JointMapping(.root, .root),
        JointMapping(.leftShoulder, .leftShoulder),
        JointMapping(.rightShoulder, .rightShoulder),
        JointMapping(.leftElbow, .leftElbow),
        JointMapping(.rightElbow, .rightElbow),
        JointMapping(.leftWrist, .leftWrist),
        JointMapping(.rightWrist, .rightWrist),
        JointMapping(.leftHip, .leftHip),
        JointMapping(.rightHip, .rightHip),
        JointMapping(.leftKnee, .leftKnee),
        JointMapping(.rightKnee, .rightKnee),
        JointMapping(.leftAnkle, .leftAnkle),
        JointMapping(.rightAnkle, .rightAnkle),
    ]
}

private struct JointMapping {
    let visionJoint: VNHumanBodyPoseObservation.JointName
    let formCheckJoint: FormCheckJointName

    init(
        _ visionJoint: VNHumanBodyPoseObservation.JointName,
        _ formCheckJoint: FormCheckJointName
    ) {
        self.visionJoint = visionJoint
        self.formCheckJoint = formCheckJoint
    }
}
#endif
