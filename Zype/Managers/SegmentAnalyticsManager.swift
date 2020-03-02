//
//  SegmentAnalyticsManager.swift
//  PeopleTV
//
//  Created by Anish Agarwal on 08/02/20.
//  Copyright © 2020 Eugene Lizhnyk. All rights reserved.
//

import Foundation
import Analytics

enum SegmentAnalyticsEventType: String {
    case PlayerStartEvent    = "Video Content Started"
    case PlayerPlayingEvent  = "Video Content Playing"
    case PlayerCompleteEvent = "Video Content Completed"
}

enum SegmentAnalyticsAttributes: String {
    case contentCmsCategory //A STRING of the CMS category attached to the piece of content, pipe separated if more than CMS category exists for the piece of content.
    case adType = "Ad Type" //a value of “pre-roll” “mid-roll” or “post-roll” if known
    case contentShownOnPlatform //"ott" (this is hardcoded)
    case streaming_device // device make + model (e.g., "Roku 4400X")
    case videoAccountId // 416418724" (this is hardcoded)
    case videoAccountName // "People" (this is hardcoded)
    case videoAdDuration // the total duration of an ad break, if known
    case videoAdVolume // the volume of an ad playing, if known
    case session_id   //String (au togenerated for the playback's session)
    case videoId     //String (Zype video_id)
    case videoName        //String (Zype video_title)
    //case description  //String (Zype video_description, if available)
    //case season       //String (Zype video_season, if available)
    //case episode      //String (Zype video_episode, if available)
    //case publisher    //String (App name)
    case videoContentPosition     //Integer (current playhead position)
    case videoContentDuration //Integer (total duration of video in seconds)
    case videoContentPercentComplete // The current  percent of video watched.
    //case channel      //String (App name)
    case livestream   //Boolean (true if on_air = true)
    case videoPublishedAt      //ISO 8601 Date String (Zype published_at date)
    case videoCreatedAt //  A TIMESTAMP of the time of video creation
    case videoSyndicate // A STRING that passes whether the piece of content is syndicated
    case videoFranchise //  A STRING that passes the video franchise. Please pass null if not available 
//    case bitrate      //Integer (The current kbps, if available)
//    case framerate    //Float (The average fps, if available)
    case videoTags     //Array(String)
    case videoThumbnail //  thumbnail URL of the primary thumbnail image
    case videoUpdatedAt // A TIMESTAMP of the video's last updated date/time
}

class SegmentAnalyticsManager: NSObject {
    // MARK: - Properties
    public static let sharedInstance = SegmentAnalyticsManager()
    private var isLiveStream: Bool = false
    private var isResumingPlayback: Bool = false
    private var segmentPayload: [String: Any]? = nil
    private var totalLength: Double = 0
    private var currentPosition: Double = 0
    private var progress: Double = 0
    private var timeObserverToken: Any?
    private var trackingTimer: Timer?
    private var sessionId = UUID().uuidString
    private static let playingHeartBeatInterval = 5.0

    weak var zypePlayer: ZypeAVPlayer? = nil
    
    
    // MARK: - reset
    open func reset() {
        removeTrackingVideoProgress()
        NotificationCenter.default.removeObserver(self)
        segmentPayload = nil
        zypePlayer = nil
        totalLength = 0
        currentPosition = 0
        progress = 0
        isLiveStream = false
        isResumingPlayback = false
    }
    
    open func setConfigurations(_ player: ZypeAVPlayer, _ payload: [String: Any], _ isLive: Bool, _ resume: Bool) {
        if !isSegmentAnalyticsEnabled() {
            return
        }
        segmentPayload = payload
        zypePlayer = player
        isLiveStream = isLive
        isResumingPlayback = resume
        segmentPayload?[SegmentAnalyticsAttributes.session_id.rawValue] = sessionId
    }
    
    // MARK: - track video playback
    open func trackStart(resumedByAd: Bool) {
        if !isSegmentAnalyticsEnabled() {
            return
        }
        
        if !isResumingPlayback {
            guard let event = eventData(.PlayerStartEvent) else {
                print("SegmentAnalyticsManager.trackStart event data is nil")
                return
            }
            SEGAnalytics.shared()?.track(SegmentAnalyticsEventType.PlayerStartEvent.rawValue, properties: event)
        }
        
        // start tracking video progress
        trackVideoProgress()
    }
    
    open func trackPause() {
        if !isSegmentAnalyticsEnabled() {
            return
        }
        removeTrackingVideoProgress()
    }
    
    open func trackComplete() {
        if !isSegmentAnalyticsEnabled() {
            return
        }
        guard let event = eventData(.PlayerCompleteEvent) else {
            print("SegmentAnalyticsManager.trackComplete event data is nil")
            return
        }
        SEGAnalytics.shared()?.track(SegmentAnalyticsEventType.PlayerCompleteEvent.rawValue, properties: event)
        
        // reset all parameters and remove observer after video playing finished
        reset()
    }

    private func trackPlaying() {
        guard let event = eventData(.PlayerPlayingEvent) else {
            print("SegmentAnalyticsManager.trackPlaying event data is nil")
            return
        }
        SEGAnalytics.shared()?.track(SegmentAnalyticsEventType.PlayerPlayingEvent.rawValue, properties: event)
    }

    private func eventData(_ event: SegmentAnalyticsEventType) -> [String:Any]? {
        guard var segmentPayload = segmentPayload else { return nil }
        
        if event == .PlayerCompleteEvent {
            segmentPayload[SegmentAnalyticsAttributes.videoContentPosition.rawValue] = Int(self.totalLength)
            segmentPayload["videoContentPercentComplete"] = Int(100)
        } else {
            segmentPayload[SegmentAnalyticsAttributes.videoContentPosition.rawValue] = Int(self.currentPosition)
            segmentPayload["videoContentPercentComplete"] = Int(self.progress)
        }
        
        segmentPayload[SegmentAnalyticsAttributes.livestream.rawValue] = isLiveStream

        print("\(event.rawValue) - \(segmentPayload)")
        return segmentPayload
    }
    
    private func trackVideoProgress() {
        setupTrackingVideoProgress()
    }
    
    @objc private func updatePlayingParameters() {
        guard self.zypePlayer?.currentItem?.status == .readyToPlay else {
            print("SegmentAnalyticsManager.trackVideoProgress video item status is not readyToPlay, do nothing")
            return
        }
        
        if let duration = self.zypePlayer?.currentItem?.duration, let ctime = self.zypePlayer?.currentItem?.currentTime() {
            if isLiveStream {
                print("SegmentAnalyticsManager.trackVideoProgress detected live streaming")
                self.currentPosition = 0
            } else {
                self.totalLength = CMTimeGetSeconds(duration)
                self.currentPosition = CMTimeGetSeconds(ctime)
                if self.totalLength <= 0 {
                    print("SegmentAnalyticsManager.trackVideoProgress totalLength is zero, possible due to live streaming, don't calculate percentage")
                } else {
                    self.progress = Double(Float(self.currentPosition/self.totalLength) * 100.0)
                }
            }
            
            DispatchQueue.main.async {
                if self.progress >= 100 {
                    self.trackComplete()
                } else {
                    if self.isResumingPlayback {
                        guard let event = self.eventData(.PlayerStartEvent) else {
                            print("SegmentAnalyticsManager.trackVideoProgress event data is nil")
                            return
                        }
                        SEGAnalytics.shared()?.track(SegmentAnalyticsEventType.PlayerStartEvent.rawValue, properties: event)
                        self.isResumingPlayback = false
                    } else {
                        self.trackPlaying()
                    }
                }
            }
        }
    }
        
    private func setupTrackingVideoProgress() {
        // first cacnel previous tracking if any
        self.removeTrackingVideoProgress()
        
        self.trackingTimer = Timer.scheduledTimer(timeInterval: SegmentAnalyticsManager.playingHeartBeatInterval,
        target: self,
        selector: #selector(updatePlayingParameters),
        userInfo: nil, repeats: true)
    }
    
    private func removeTrackingVideoProgress() {
        if self.trackingTimer?.isValid == true {
            self.trackingTimer?.invalidate()
            self.trackingTimer = nil
        }
    }
    
    private func isSegmentAnalyticsEnabled() -> Bool {
        return Const.kSegmentAnalytics && Const.kSegmentAccountID.count > 0
    }
}
