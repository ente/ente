---
title: Import from Amazon Photos
description: Migrating your existing photos from Amazon Photos to Ente Photos
---

# Import from Amazon Photos

Migrating from Amazon Photos to Ente requires downloading your photos from Amazon first, then uploading them to Ente. Amazon Photos has no download-everything button. On the web you select photos and click **Download**. Amazon says you cannot download a whole album at once: open the album and select the photos inside it ([Amazon Photos download help](https://www.amazon.com/gp/help/customer/display.html?nodeId=TSaUJYyAos1A1BkziF)). For a large library, download in batches, by album or by year, and check counts as you go.

## Before you start

- Use a computer, not a phone. Batches are easier to manage, and the files land in folders you can see.
- Check free disk space. You need at least as much space as the library uses in Amazon Photos. An external drive is fine.
- Make a folder per batch, such as `2019`, `2020`, or `Wedding`. That keeps the download organized and makes it obvious what is already done.

## Understanding Amazon's limitations

Select and download photos in batches. There is no one-click export of the whole library.

Amazon also makes desktop apps for Windows and Mac ([Amazon Photos desktop apps](https://www.amazon.com/gp/help/customer/display.html?nodeId=G6PT8TMLM9NVZCSL)). Those help pages do not describe a full-library download, so the web steps below are the documented route. Amazon has separate help pages for downloading in the Android and iOS apps.

## Migration Process

### Step 1: Download from Amazon Photos

1. Open [Amazon Photos](https://www.amazon.com/photos) on a computer and sign in.
2. Open an album, or filter the library by date.
3. Select the photos and videos to download. Very large selections can be slow, so smaller batches are easier to retry.
4. Click **Download** and save the file. Larger selections usually arrive as a ZIP.
5. Unzip it into that batch's folder.
6. Repeat until the library is covered.

Keep a simple list of what you have downloaded. It is easy to lose track partway through a large library.

### Step 2: Check the download

Compare the number of files in your folders with the count Amazon shows. Spot-check some videos. Videos count toward the storage limit for everyone, Prime members included, while Prime photos do not ([Amazon Photos storage limits](https://www.amazon.co.uk/gp/help/customer/display.html?nodeId=GC4942XQ5M2T7HGF)). Open a few photos and check that the date and location came through.

### Step 3: Organize your downloads (optional)

Before uploading to Ente, you might want to:

- Organize photos into folders by date, event, or album
- Remove duplicates if any were created during download
- Delete unwanted screenshots or photos you no longer need

This organization will be reflected in Ente if you choose the **Separate albums** option during upload.

### Step 4: Upload to Ente

1. Download and install the [Ente desktop app](https://ente.com/download/)
2. Sign in to your Ente account
3. Drag and drop the downloaded folder(s) into the Ente app
4. Choose how to organize: single album or separate albums per folder
5. Review the photo, video, and album counts, then start the upload
6. Expand the progress card if you want to review completed, skipped, or failed files

Learn more about the review, progress, stop, completion, and retry screens in [Import from Local Hard Disk](/photos/migration/from-local-hard-disk).

**Upload features:**

- **Resumable**: If an upload is interrupted, drag and drop the same folder again. Ente skips files already uploaded to that album.
- **Original quality**: Your photos are uploaded in their original quality with no compression.
- **Metadata preserved**: Photo dates and locations are maintained.

## Timeline Expectations

- **Small library (< 10 GB)**: A few hours
- **Medium library (10-100 GB)**: Several hours to a day
- **Large library (> 100 GB)**: May take several days depending on your internet speed

You can use your computer while uploads run in the background.

## What about albums?

Amazon Photos albums are not preserved automatically. Download each album into its own folder, then choose **Separate albums** during upload. Each folder becomes its own album.

## Before you cancel Amazon Photos

Leave the Amazon Photos library in place until you have checked Ente.

The account drops to 5 GB of free storage when the last qualifying plan or membership is cancelled. Prime, an Alexa+ standalone subscription, and a paid Amazon Photos storage plan each keep their own entitlement, so cancelling only one of them does not drop the account to 5 GB while another remains ([Amazon Photos features](https://www.amazon.com/gp/help/customer/display.html?nodeId=GLSS4222BAQWWB3S), [Amazon Photos storage limits](https://www.amazon.com/gp/help/customer/display.html?nodeId=GC4942XQ5M2T7HGF)). If the library is over the limit that remains, Amazon says you can still view and download it, but the account is over quota and items must be removed to get back under the limit. Download first, then cancel.

## After Migration

Once your photos are in Ente:

- [Set up automatic backup](/photos/getting-started/daily-use) for new photos on your mobile devices
- Consider [enabling machine learning](/photos/features/search-and-discovery/machine-learning) for face recognition and smart search
- Explore [sharing features](/photos/features/sharing-and-collaboration/share) to share albums with family and friends

## FAQs

### Is there a way to export everything in one go? {#amazon-no-single-export}

Not from Amazon's own help pages. Batch download is the documented route.

### Will my albums come across? {#amazon-albums-across}

Only if you download album by album into separate folders, then upload with **Separate albums**.

### What about duplicates? {#amazon-batch-duplicates}

If the same photo was downloaded twice, in two batches, Ente skips a file that is already in the same album. Ente also stores a file once when that file is in several albums. Learn more in [How does Ente deduplicate photos?](/photos/faq/storage-and-plans#deduplication).

## Need Help?

If you run into any issues during this migration, please reach out to [support@ente.com](mailto:support@ente.com) and we will be happy to help you!
